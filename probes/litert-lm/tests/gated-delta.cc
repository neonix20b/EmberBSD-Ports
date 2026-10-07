// SPDX-License-Identifier: MIT
// Golden values exercise the upstream backport, including recurrent state.
#include <cmath>
#include <iostream>
#include <vector>
#include "litert/experimental/custom_ops/gated_delta_net/gated_delta_update_impl.h"

bool Equal(const float* actual, const std::vector<float>& expected) {
  for (size_t i = 0; i < expected.size(); ++i) {
    if (!std::isfinite(actual[i]) || std::fabs(actual[i] - expected[i]) > 1e-5f)
      return false;
  }
  return true;
}

int main() {
  using namespace litert::gated_delta_net;
  // Strictly lower A; the kernel forms I + A + A^2 (A^3 = 0).
  const float triangular[] = {0, 0, 0, 2, 0, 0, 3, 4, 0};
  float inverse[9];
  ComputeTrilInv(triangular, inverse, 9, 3);
  if (!Equal(inverse, {1, 0, 0, 2, 1, 0, 11, 4, 1})) return 1;

  // Step 1 writes v to row 0; step 2 decays it by 1/2 and writes row 1.
  // q reads both rows, testing that the recurrent state survives the sequence.
  const float q[] = {1, 1, 1, 1};
  const float k[] = {1, 0, 0, 1};
  const float v[] = {2, 4, 6, 8};
  const float beta[] = {1, 1};
  const float g[] = {0, std::log(0.5f)};
  const float state[] = {0, 0, 0, 0};
  float output[4], next[4];
  ComputeGatedDeltaUpdateRecurrent(q, k, v, beta, g, state, output, next,
                                   1, 1, 2, 2, 2);
  if (!Equal(output, {2, 4, 7, 10}) || !Equal(next, {1, 2, 6, 8})) return 1;
  ComputeGatedDeltaUpdateChunked(q, k, v, beta, g, state, output, next,
                                 1, 1, 2, 2, 2);
  if (!Equal(output, {2, 4, 7, 10}) || !Equal(next, {1, 2, 6, 8})) return 1;

  // Cross the upstream 64-token chunk boundary with a closed-form state:
  // k=q=beta=1, g=0 makes each output and the final state equal to v_t.
  std::vector<float> ones(65, 1), zeros(65, 0), values(65), out(65);
  for (int i = 0; i < 65; ++i) values[i] = static_cast<float>(i + 1);
  float scalar_state = 3, scalar_next = 0;
  ComputeGatedDeltaUpdateChunked(ones.data(), ones.data(), values.data(),
      ones.data(), zeros.data(), &scalar_state, out.data(), &scalar_next,
      1, 1, 65, 1, 1);
  if (!Equal(out.data(), values) || scalar_next != 65) return 1;
  std::cout << "PASS: GatedDeltaNet triangular, recurrent and chunk-boundary values\n";
  return 0;
}
