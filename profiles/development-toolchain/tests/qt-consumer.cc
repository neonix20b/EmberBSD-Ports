/* SPDX-License-Identifier: BSD-2-Clause */
#include <QCoreApplication>
#include <QString>
#include <cassert>
#include <cstdio>
#include <link.h>
#include <string>

static int loaded(struct dl_phdr_info *info, size_t, void *)
{
    if (info->dlpi_name && info->dlpi_name[0])
        std::printf("LOADED %s\n", info->dlpi_name);
    return 0;
}

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    const std::string input(128, 'x');
    const auto text = QString::fromStdString(input);
    assert(text.toStdString() == input);
    assert((text + QStringLiteral(":qt")).toStdString() == input + ":qt");
    dl_iterate_phdr(loaded, nullptr);
}
