/* SPDX-License-Identifier: BSD-2-Clause */
/* The generated include contains verbatim functions from Enlightenment.
 * Only external effects are replaced by counters in this test process. */
#include <assert.h>
#include <stdio.h>
#include <stddef.h>

typedef unsigned int Eina_Bool;
#define EINA_TRUE 1
#define EINA_FALSE 0
#define E_API
#define EINTERN
#define E_BITFIELD : 1
#if defined(__clang__) || (defined(__GNUC__) && __GNUC__ >= 7)
#define EINA_FALLTHROUGH __attribute__((fallthrough))
#else
#define EINA_FALLTHROUGH ((void)0)
#endif
#define E_TYPEDEFS
#include "e_sys.h"
#undef E_TYPEDEFS
/* Exclude the unrelated RandR branch when exercising helper queue accounting. */
#define HAVE_WAYLAND_ONLY 1
#define ERR(...) (++diagnostics)

static int diagnostics, backend_calls, save_calls, dialog_calls, lock_calls;
static int helper_calls, handler_calls, clear_calls, _devices_pending_ops;
static int _e_sys_can_halt = 1, _e_sys_can_reboot = 1;
static int _e_sys_can_suspend = 1, _e_sys_can_hibernate = 1;
static int _e_sys_can_hybrid_suspend = 1, _e_sys_can_suspend_then_hibernate = 1;
static E_Sys_Action _e_sys_action_current = E_SYS_NONE;
static Eina_Bool on_the_way_out, _e_desklock_want, desklock_manual;
static int _e_desklock_block;
static struct { int suspend_mode; } config = { 0 }, *e_config = &config;

static int
_e_sys_action_do(E_Sys_Action action, char *param, Eina_Bool raw)
{
    (void)action; (void)param; (void)raw;
    backend_calls++;
    return 1;
}
static void e_config_save_flush(void) { save_calls++; }
static void _e_sys_current_action(void) { dialog_calls++; }
static int e_util_immortal_check(void) { return 0; }
static int _desklock_show_internal(Eina_Bool suspend)
{
    (void)suspend;
    lock_calls++;
    return 1;
}
static void _backlight_devices_clear(void) { clear_calls++; }
static void _backlight_system_list_cb(void *data, const char *params)
{ (void)data; (void)params; }
static void _backlight_system_ddc_list_cb(void *data, const char *params)
{ (void)data; (void)params; }
static void e_system_handler_add(const char *cmd,
    void (*cb)(void *, const char *), void *data)
{ (void)cmd; (void)cb; (void)data; handler_calls++; }
static void e_system_handler_del(const char *cmd,
    void (*cb)(void *, const char *), void *data)
{ (void)cmd; (void)cb; (void)data; handler_calls++; }
static void e_system_send(const char *cmd, const char *fmt, ...)
{ (void)cmd; (void)fmt; helper_calls++; }

#include "actual-functions.inc"

static void
reset_effects(void)
{
    diagnostics = backend_calls = save_calls = dialog_calls = 0;
    on_the_way_out = EINA_FALSE;
    _e_sys_action_current = E_SYS_NONE;
}

int
main(void)
{
    const E_Sys_Action power[] = {
        E_SYS_HALT, E_SYS_HALT_NOW, E_SYS_REBOOT, E_SYS_SUSPEND,
        E_SYS_HIBERNATE, E_SYS_HYBRID_SUSPEND,
        E_SYS_SUSPEND_THEN_HIBERNATE, E_SYS_SUSPEND_MODE
    };
    const E_Sys_Action local[] = {
        E_SYS_EXIT, E_SYS_RESTART, E_SYS_EXIT_NOW, E_SYS_LOGOUT
    };
    size_t i;
    int raw, result;

    assert(e_system_services_enabled_get() == E_SYSTEM_SERVICES);
    for (i = 0; i < sizeof(power) / sizeof(power[0]); i++) {
        /* All backend capabilities deliberately true: policy must override them. */
        assert(e_sys_action_possible_get(power[i]) == E_SYSTEM_SERVICES);
        for (raw = 0; raw <= 1; raw++) {
            reset_effects();
            result = raw ? e_sys_action_raw_do(power[i], NULL) :
                e_sys_action_do(power[i], NULL);
            assert(result == E_SYSTEM_SERVICES);
            assert(backend_calls == E_SYSTEM_SERVICES);
            assert(save_calls == E_SYSTEM_SERVICES);
            assert(dialog_calls == 0);
            if (!E_SYSTEM_SERVICES) {
                assert(diagnostics == 1);
                assert(_e_sys_action_current == E_SYS_NONE);
                assert(on_the_way_out == EINA_FALSE);
            }
        }
    }
    for (i = 0; i < sizeof(local) / sizeof(local[0]); i++) {
        assert(e_sys_action_possible_get(local[i]) == 1);
        for (raw = 0; raw <= 1; raw++) {
            reset_effects();
            result = raw ? e_sys_action_raw_do(local[i], NULL) :
                e_sys_action_do(local[i], NULL);
            assert(result == 1);
            assert(backend_calls == 1 && save_calls == 1);
            assert(diagnostics == 0);
        }
    }
    reset_effects();
    assert(e_desklock_show(EINA_FALSE) == E_SYSTEM_SERVICES);
    assert(lock_calls == E_SYSTEM_SERVICES);
    assert(_e_desklock_want == E_SYSTEM_SERVICES);
    assert(diagnostics == !E_SYSTEM_SERVICES);

    _backlight_devices_probe(EINA_TRUE);
    assert(clear_calls == 1);
    assert(_devices_pending_ops == 2 * E_SYSTEM_SERVICES);
    assert(helper_calls == 2 * E_SYSTEM_SERVICES);
    assert(handler_calls == 4 * E_SYSTEM_SERVICES);
    _devices_pending_ops = helper_calls = handler_calls = 0;
    _backlight_devices_probe(EINA_FALSE);
    assert(_devices_pending_ops == 2 * E_SYSTEM_SERVICES);
    assert(helper_calls == 4 * E_SYSTEM_SERVICES);
    assert(handler_calls == 4 * E_SYSTEM_SERVICES);
    printf("PASS: actual-source system-services=%d policy, lock and helper queue\n",
        E_SYSTEM_SERVICES);
    return 0;
}
