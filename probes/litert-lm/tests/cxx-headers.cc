// SPDX-License-Identifier: MIT
// Public return types must remain usable by a standard C++20 consumer.
#include <type_traits>
#include <utility>

#include "litert/cc/litert_buffer_ref.h"
#include "litert/cc/litert_model_types.h"

static_assert(std::is_same_v<
    decltype(std::declval<const litert::BufferRef<unsigned char>&>().Span()),
    litert::Span<const unsigned char>>);
static_assert(std::is_same_v<
    decltype(std::declval<litert::MutableBufferRef<unsigned char>&>().Span()),
    litert::Span<unsigned char>>);
static_assert(std::is_same_v<
    decltype(std::declval<const litert::SimpleTensor&>().ElementType()),
    litert::ElementType>);
static_assert(std::is_same_v<
    decltype(std::declval<const litert::SimpleTensor&>().RankedTensorType()),
    litert::Expected<litert::RankedTensorType>>);
