#pragma once

#include "rust/cxx.h"

// Application name, version and Wayland app id; call after the QGuiApplication exists.
void bindaru_describe_application(rust::Str version);
// Whether QML created a window.
bool bindaru_has_window();
