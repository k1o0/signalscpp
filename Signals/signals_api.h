#pragma once
#ifndef SIGNALS_API_H
#define SIGNALS_API_H

#if defined(SIGNALS_STATIC_LIB)
#define SIGNALS_API
#elif defined(_WIN32)
#if defined(SIGNALS_EXPORTS)
#define SIGNALS_API __declspec(dllexport)
#else
#define SIGNALS_API __declspec(dllimport)
#endif
#elif defined(__GNUC__) || defined(__clang__)
#define SIGNALS_API __attribute__((visibility("default")))
#else
#define SIGNALS_API
#endif

#endif
