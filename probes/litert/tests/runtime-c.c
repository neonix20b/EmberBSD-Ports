/* SPDX-License-Identifier: MIT */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "litert/c/litert_compiled_model.h"
#include "litert/c/litert_environment.h"
#include "litert/c/litert_model.h"
#include "litert/c/litert_options.h"
#include "litert/c/litert_tensor_buffer.h"
#include "litert/c/litert_tensor_buffer_requirements.h"
#include "runtime-vectors.h"

static void
require(int condition, const char *message)
{
	if (!condition) {
		fprintf(stderr, "FAIL: %s\n", message);
		exit(EXIT_FAILURE);
	}
}

static void
status_ok(LiteRtStatus status, const char *operation)
{
	if (status != kLiteRtStatusOk) {
		fprintf(stderr, "FAIL: %s returned status %d\n", operation, (int)status);
		exit(EXIT_FAILURE);
	}
}
#define OK(operation) status_ok((operation), #operation)

static void
check_layout(const LiteRtLayout *layout)
{
	require(layout->rank == 2 && layout->dimensions[0] == 1 &&
	    layout->dimensions[1] == kRuntimeElements && !layout->has_strides,
	    "fixture tensor layout must be dense [1,4]");
}

static void
reject_models(LiteRtEnvironment env, const char *model_path)
{
	static const unsigned char malformed[32] = "not a TFLite FlatBuffer";
	size_t size = strlen(model_path) + sizeof("/missing.tflite");
	char *missing_path = malloc(size);
	LiteRtModel rejected = NULL;

	require(missing_path != NULL, "allocate missing path");
	snprintf(missing_path, size, "%s/missing.tflite", model_path);
	require(LiteRtCreateModelFromFile(env, missing_path, &rejected) !=
	    kLiteRtStatusOk,
	    "a child path under the regular fixture file must fail to load");
	if (rejected != NULL)
		LiteRtDestroyModel(rejected);
	free(missing_path);
	rejected = NULL;
	require(LiteRtCreateModelFromBuffer(env, malformed, sizeof(malformed),
	    &rejected) != kLiteRtStatusOk,
	    "malformed model bytes must be rejected");
	if (rejected != NULL)
		LiteRtDestroyModel(rejected);
	puts("PASS: C missing and malformed model rejection");
}

static LiteRtTensorBuffer
make_buffer(LiteRtEnvironment env,
    LiteRtCompiledModel compiled,
    LiteRtSubgraph graph, int output,
    LiteRtParamIndex index)
{
	LiteRtTensor tensor;
	LiteRtTensorBufferRequirements requirements;
	LiteRtRankedTensorType type;
	LiteRtTensorBuffer buffer;
	int num_types, has_host = 0;
	size_t bytes, packed_bytes;

	if (output) {
		OK(LiteRtGetSubgraphOutput(graph, index, &tensor));
		OK(LiteRtGetCompiledModelOutputBufferRequirements(compiled, 0, index,
		    &requirements));
	} else {
		OK(LiteRtGetSubgraphInput(graph, index, &tensor));
		OK(LiteRtGetCompiledModelInputBufferRequirements(compiled, 0, index,
		    &requirements));
	}
	OK(LiteRtGetRankedTensorType(tensor, &type));
	require(type.element_type == kLiteRtElementTypeFloat32,
	    "fixture tensor must contain float32");
	check_layout(&type.layout);
	OK(LiteRtGetNumTensorBufferRequirementsSupportedBufferTypes(requirements,
	    &num_types));
	for (int i = 0; i < num_types; ++i) {
		LiteRtTensorBufferType buffer_type;
		OK(LiteRtGetTensorBufferRequirementsSupportedTensorBufferType(
		    requirements, i, &buffer_type));
		has_host |= buffer_type == kLiteRtTensorBufferTypeHostMemory;
	}
	require(has_host, "explicit CPU model must accept host tensor buffers");
	OK(LiteRtGetTensorBufferRequirementsBufferSize(requirements, &bytes));
	require(bytes >= sizeof(runtime_sum[0]), "required buffer holds four floats");
	OK(LiteRtCreateManagedTensorBuffer(env, kLiteRtTensorBufferTypeHostMemory,
	    &type, bytes, &buffer));
	OK(LiteRtGetTensorBufferPackedSize(buffer, &packed_bytes));
	require(packed_bytes == sizeof(runtime_sum[0]), "packed size is four floats");
	return buffer;
}

static void
reject_buffers(void)
{
	LiteRtRankedTensorType type = {0};
	void *memory = NULL;
	LiteRtTensorBuffer buffer = NULL;

	type.element_type = kLiteRtElementTypeFloat32;
	type.layout.rank = 2;
	type.layout.dimensions[0] = 1;
	type.layout.dimensions[1] = kRuntimeElements;
	require(posix_memalign(&memory, LITERT_HOST_MEMORY_BUFFER_ALIGNMENT, 128) == 0,
	    "allocate aligned host test memory");
	require(LiteRtCreateTensorBufferFromHostMemory(
	    &type, memory, sizeof(runtime_sum[0]) - 1, NULL, &buffer) !=
	    kLiteRtStatusOk,
	    "undersized host buffer must be rejected");
	if (buffer != NULL)
		LiteRtDestroyTensorBuffer(buffer);
	buffer = NULL;
	require(LiteRtCreateTensorBufferFromHostMemory(
	    &type, (char *)memory + 1, sizeof(runtime_sum[0]), NULL, &buffer) !=
	    kLiteRtStatusOk,
	    "misaligned host buffer must be rejected");
	if (buffer != NULL)
		LiteRtDestroyTensorBuffer(buffer);
	buffer = NULL;
	type.layout.dimensions[1] = -1;
	require(LiteRtCreateTensorBufferFromHostMemory(
	    &type, memory, sizeof(runtime_sum[0]), NULL, &buffer) !=
	    kLiteRtStatusOk,
	    "a host tensor buffer needs concrete dimensions");
	if (buffer != NULL)
		LiteRtDestroyTensorBuffer(buffer);
	free(memory);
	puts("PASS: C undersized, misaligned and dynamic-layout buffer rejection");
}

static void
write_buffer(LiteRtTensorBuffer buffer, const float *values)
{
	void *memory;

	OK(LiteRtLockTensorBuffer(buffer, &memory, kLiteRtTensorBufferLockModeWrite));
	memcpy(memory, values, sizeof(runtime_sum[0]));
	OK(LiteRtUnlockTensorBuffer(buffer));
}

int
main(int argc, char **argv)
{
	LiteRtEnvironment env;
	LiteRtModel model;
	LiteRtOptions options;
	LiteRtHwAcceleratorSet selected;
	LiteRtCompiledModel compiled;
	LiteRtSubgraph graph;
	LiteRtParamIndex count;
	LiteRtLayout layout;
	LiteRtTensorBuffer inputs[2], outputs[1];

	if (argc != 2) {
		fprintf(stderr, "usage: %s runtime-add.tflite\n", argv[0]);
		return 2;
	}
	OK(LiteRtCreateEnvironment(0, NULL, &env));
	OK(LiteRtCreateModelFromFile(env, argv[1], &model));
	reject_models(env, argv[1]);
	reject_buffers();
	OK(LiteRtCreateOptions(&options));
	OK(LiteRtSetOptionsHardwareAccelerators(options, kLiteRtHwAcceleratorCpu));
	OK(LiteRtGetOptionsHardwareAccelerators(options, &selected));
	require(selected == kLiteRtHwAcceleratorCpu, "CPU must be selected explicitly");
	OK(LiteRtCreateCompiledModel(env, model, options, &compiled));
	LiteRtDestroyOptions(options);
	OK(LiteRtGetModelSubgraph(model, 0, &graph));
	OK(LiteRtGetNumSubgraphInputs(graph, &count));
	require(count == 2, "fixture has two inputs");
	OK(LiteRtGetNumSubgraphOutputs(graph, &count));
	require(count == 1, "fixture has one output");
	OK(LiteRtGetNumModelSignatures(model, &count));
	require(count == 1, "fixture has one signature");
	OK(LiteRtGetCompiledModelInputTensorLayout(compiled, 0, 0, &layout));
	check_layout(&layout);
	OK(LiteRtGetCompiledModelOutputTensorLayouts(compiled, 0, 1, &layout, false));
	check_layout(&layout);
	inputs[0] = make_buffer(env, compiled, graph, 0, 0);
	inputs[1] = make_buffer(env, compiled, graph, 0, 1);
	outputs[0] = make_buffer(env, compiled, graph, 1, 0);
	require(LiteRtRunCompiledModel(compiled, 999, 2, inputs, 1, outputs) !=
	    kLiteRtStatusOk,
	    "invalid signature must be rejected");
	require(LiteRtRunCompiledModel(compiled, 0, 1, inputs, 1, outputs) !=
	    kLiteRtStatusOk,
	    "missing input buffer must be rejected");
	for (int n = 0; n < kRuntimeCases; ++n) {
		void *memory;
		const float *actual;

		write_buffer(inputs[0], runtime_x[n]);
		write_buffer(inputs[1], runtime_y[n]);
		OK(LiteRtRunCompiledModel(compiled, 0, 2, inputs, 1, outputs));
		OK(LiteRtLockTensorBuffer(outputs[0], &memory,
		    kLiteRtTensorBufferLockModeRead));
		actual = memory;
		for (int i = 0; i < kRuntimeElements; ++i) {
			if (actual[i] != runtime_sum[n][i]) {
				fprintf(stderr, "FAIL: C run %d element %d: %.9g, expected %.9g\n",
				    n, i, actual[i], runtime_sum[n][i]);
				return EXIT_FAILURE;
			}
		}
		OK(LiteRtUnlockTensorBuffer(outputs[0]));
	}
	LiteRtDestroyCompiledModel(compiled);
	LiteRtDestroyTensorBuffer(outputs[0]);
	LiteRtDestroyTensorBuffer(inputs[1]);
	LiteRtDestroyTensorBuffer(inputs[0]);
	LiteRtDestroyModel(model);
	LiteRtDestroyEnvironment(env);
	puts("PASS: C CPU ADD, 3 changed input pairs, 12 exact sums; error recovery");
	return EXIT_SUCCESS;
}
