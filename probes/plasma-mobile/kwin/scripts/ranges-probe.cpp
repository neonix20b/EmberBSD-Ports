#include "utils/ranges.h"
#include <QList>
#include <QMap>
#include <QStringList>
#include <algorithm>
#include <cassert>
#include <memory>
#include <vector>

struct Base { virtual ~Base() = default; };
struct Derived : Base {};

int main()
{
    const std::vector<int> source{1, 2, 3, 4};
    const auto transformed = source
        | std::views::filter([](int value) { return value % 2 == 0; })
        | std::views::transform([](int value) { return value * 3; })
        | KWin::toContainer<QList>();
    assert((transformed == QList<int>{6, 12}));
    const std::vector<int> empty;
    assert((empty | KWin::toContainer<std::vector>()).empty());
    Derived value;
    const std::vector<Derived *> pointers{&value};
    const auto converted = pointers | KWin::toContainer<QList<Base *>>();
    assert(converted.size() == 1 && converted[0] == &value);
    const QMap<int, QString> map{{1, QStringLiteral("one")}, {2, QStringLiteral("two")}};
    const auto text = map | KWin::toContainer<QStringList>();
    assert((text == QStringList{QStringLiteral("one"), QStringLiteral("two")}));
    std::vector<std::unique_ptr<int>> owned;
    owned.push_back(std::make_unique<int>(42));
    const auto raw = owned | std::views::transform(&std::unique_ptr<int>::get) | KWin::toContainer<QList>();
    assert(raw.size() == 1 && *raw[0] == 42 && *owned[0] == 42);
}
