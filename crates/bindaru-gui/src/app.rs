//! Application setup in C++ (see `cpp/app.cpp`).

#[cxx::bridge]
pub mod ffi {
    unsafe extern "C++" {
        include!("bindaru-gui/cpp/app.h");

        fn bindaru_describe_application(version: &str);
        fn bindaru_has_window() -> bool;
        fn bindaru_forward_to_running() -> bool;
    }
}
