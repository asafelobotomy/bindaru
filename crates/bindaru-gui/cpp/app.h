#pragma once

#include "rust/cxx.h"

// Application name, version and Wayland app id; call after the QGuiApplication exists.
void bindaru_describe_application(rust::Str version);
// Whether QML created a window.
bool bindaru_has_window();
// One window per session: true when another bindaru window is already open in this session (it
// has been asked to come forward, so this start should exit); false when this start now owns the
// session's window. Call after the QGuiApplication exists.
bool bindaru_forward_to_running();
