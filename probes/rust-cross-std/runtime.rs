use std::cell::{Cell, RefCell};
use std::sync::atomic::{AtomicUsize, Ordering};
static DROPS: AtomicUsize = AtomicUsize::new(0);
struct Marker;
impl Drop for Marker {
    fn drop(&mut self) { DROPS.fetch_add(1, Ordering::SeqCst); }
}
thread_local! {
    static VALUE: Cell<usize> = const { Cell::new(0) };
    static MARKER: RefCell<Option<Marker>> = const { RefCell::new(None) };
}
unsafe extern "C" { fn getpid() -> i32; }
fn exercise() {
    assert!(unsafe { getpid() } > 0);
    VALUE.with(|value| { assert_eq!(value.get(), 0); value.set(0xc0de); });
    let barrier = std::sync::Arc::new(std::sync::Barrier::new(8));
    let previous = DROPS.load(Ordering::SeqCst);
    let workers: Vec<_> = (0..8usize).map(|index| { let barrier = barrier.clone(); std::thread::spawn(move || {
        MARKER.with(|slot| *slot.borrow_mut() = Some(Marker));
        VALUE.with(|value| assert_eq!(value.get(), 0));
        barrier.wait();
        let bytes = vec![index as u8 + 1; 4096];
        for n in 1..=512 {
            VALUE.with(|value| { value.set(value.get() + 1); assert_eq!(value.get(), n); });
            if n % 16 == 0 { std::thread::yield_now(); }
        }
        let err = std::panic::catch_unwind(|| std::panic::panic_any(index + 37)).unwrap_err();
        assert_eq!(*err.downcast::<usize>().unwrap(), index + 37);
        bytes.iter().map(|v| usize::from(*v)).sum::<usize>()
    }) }).collect();
    let total: usize = workers.into_iter().map(|t| t.join().unwrap()).sum();
    assert_eq!(total, 4096 * 36);
    assert_eq!(DROPS.load(Ordering::SeqCst) - previous, 8);
    VALUE.with(|value| { assert_eq!(value.get(), 0xc0de); value.set(0); });
}
#[unsafe(no_mangle)]
pub extern "C" fn ember_rust_check() -> u32 {
    MARKER.with(|slot| {
        let mut marker = slot.borrow_mut();
        if marker.is_none() { *marker = Some(Marker); }
    });
    let old_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(|_| {}));
    let result = std::panic::catch_unwind(exercise);
    std::panic::set_hook(old_hook);
    if result.is_ok() { 0 } else { 1 }
}
#[unsafe(no_mangle)]
pub extern "C" fn ember_rust_drops() -> u32 {
    DROPS.load(Ordering::SeqCst) as u32
}
#[allow(dead_code)]
fn main() {
    for _ in 0..4 { assert_eq!(ember_rust_check(), 0); }
    println!("PASS: Rust allocation, C ABI, 32 joined threads, TLS isolation/destructors, unwind");
}
