// DatostimProxy.cpp — MEX proxy that reads network node values and drives a
// datostim window without any MATLAB engine round-trips in the draw path.
//
// datostim.dll is loaded at runtime via LoadLibrary/GetProcAddress so that
// the signalsproxy.dll can be built with MSVC without a datoviz import lib.

#include "DatostimProxy.h"
#include "NetworkProxy.h"
#include "mex_value_traits.h"

#include "MatlabDataArray.hpp"

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>

#include <cmath>
#include <cstring>
#include <csignal>
#include <setjmp.h>
#include <string>
#include <vector>

namespace sq::proxy {

// ---------------------------------------------------------------------------
// Column-major 4×4 matrix math (no cglm dependency in the proxy)
// mat4[col][row] — matches cglm layout used by datostim.
// ---------------------------------------------------------------------------

namespace {

using Mat4 = float[4][4];

static void mat4_identity(Mat4 m) {
    memset(m, 0, sizeof(Mat4));
    m[0][0] = m[1][1] = m[2][2] = m[3][3] = 1.0f;
}

// out = a * b  (column-major: applies b first, then a)
static void mat4_mul(const Mat4 a, const Mat4 b, Mat4 out) {
    float tmp[4][4] = {};
    for (int col = 0; col < 4; col++)
        for (int row = 0; row < 4; row++)
            for (int k = 0; k < 4; k++)
                tmp[col][row] += a[k][row] * b[col][k];
    memcpy(out, tmp, sizeof(Mat4));
}

static void mat4_rot_x(float a, Mat4 m) {
    float c = cosf(a), s = sinf(a);
    mat4_identity(m);
    m[1][1] =  c;  m[1][2] = s;
    m[2][1] = -s;  m[2][2] = c;
}

static void mat4_rot_y(float a, Mat4 m) {
    float c = cosf(a), s = sinf(a);
    mat4_identity(m);
    m[0][0] = c;   m[0][2] = -s;
    m[2][0] = s;   m[2][2] =  c;
}

static void mat4_rot_z(float a, Mat4 m) {
    float c = cosf(a), s = sinf(a);
    mat4_identity(m);
    m[0][0] =  c;  m[0][1] = s;
    m[1][0] = -s;  m[1][1] = c;
}

static constexpr float DEG2RAD = 3.14159265358979323846f / 180.0f;

// ---------------------------------------------------------------------------
// Safe field accessors — return defaults on any type mismatch or empty array
// ---------------------------------------------------------------------------

static float field_float(const matlab::data::StructArray& sa,
                          const std::string& name, float def = 0.0f) {
    try {
        matlab::data::Array f = sa[0][name];
        if (f.isEmpty()) return def;
        matlab::data::TypedArray<double> ta = f;
        return static_cast<float>(double(ta[0]));
    } catch (...) { return def; }
}

static bool field_bool(const matlab::data::StructArray& sa,
                        const std::string& name, bool def = false) {
    try {
        matlab::data::Array f = sa[0][name];
        if (f.isEmpty()) return def;
        try {
            matlab::data::TypedArray<bool> ta = f;
            return bool(ta[0]);
        } catch (...) {
            matlab::data::TypedArray<double> ta = f;
            return double(ta[0]) != 0.0;
        }
    } catch (...) { return def; }
}

static std::string field_string(const matlab::data::StructArray& sa,
                                 const std::string& name) {
    try {
        matlab::data::Array f = sa[0][name];
        if (f.isEmpty()) return {};
        matlab::data::CharArray ca = f;
        return ca.toAscii();
    } catch (...) { return {}; }
}

static uint8_t clamp_u8(double v) {
    return static_cast<uint8_t>(
        static_cast<int>(std::max(0.0, std::min(255.0, v * 255.0 + 0.5))));
}

// ---------------------------------------------------------------------------
// SIGABRT interception — catches dvz_assert→abort() so MATLAB doesn't die.
// thread_local so nested or concurrent calls (MEX background threads) stay safe.
// ---------------------------------------------------------------------------

thread_local jmp_buf tls_abort_env;
thread_local bool    tls_abort_armed = false;

static void abort_interception(int) {
    if (tls_abort_armed) {
        tls_abort_armed = false;
        longjmp(tls_abort_env, 1);
    }
}

} // anonymous namespace

// ---------------------------------------------------------------------------
// Construction / destruction
// ---------------------------------------------------------------------------

DatostimProxy::DatostimProxy(std::shared_ptr<MexNetwork> net,
                             DStim* stim, void* dll_handle, DatostimAPI api,
                             std::string datostim_dir)
    : net_{std::move(net)}, stim_{stim}, dll_handle_{dll_handle}, api_{api},
      datostim_dir_{std::move(datostim_dir)}
{
    REGISTER_METHOD(DatostimProxy, WatchLayer);
    REGISTER_METHOD(DatostimProxy, Draw);
    REGISTER_METHOD(DatostimProxy, SetBackground);
    REGISTER_METHOD(DatostimProxy, SetScreen);
    REGISTER_METHOD(DatostimProxy, GetTime);
    REGISTER_METHOD(DatostimProxy, Cleanup);
}

DatostimProxy::~DatostimProxy() {
    if (stim_ && api_.cleanup) {
        api_.cleanup(stim_);
        stim_ = nullptr;
    }
    if (dll_handle_) {
        FreeLibrary(static_cast<HMODULE>(dll_handle_));
        dll_handle_ = nullptr;
    }
}

libmexclass::proxy::MakeResult DatostimProxy::make(
    const libmexclass::proxy::FunctionArguments& args)
{
    if (args.getNumberOfElements() < 4) {
        return libmexclass::error::Error{
            "sq:datostim:badArgs",
            "DatostimProxy requires (net_proxy_id, width, height, dll_path)"};
    }

    matlab::data::CellArray cell = args;

    matlab::data::TypedArray<uint64_t> id_arr = cell[0];
    auto net_handle = static_cast<uintptr_t>(uint64_t(id_arr[0]));

    matlab::data::TypedArray<double> w_arr = cell[1];
    matlab::data::TypedArray<double> h_arr = cell[2];
    auto width  = static_cast<uint32_t>(double(w_arr[0]));
    auto height = static_cast<uint32_t>(double(h_arr[0]));

    matlab::data::CharArray path_arr = cell[3];
    std::string dll_path = path_arr.toAscii();

    // Retrieve MexNetwork from the in-DLL registry (keyed by raw pointer value).
    auto net = NetworkProxy::getNetworkByHandle(net_handle);
    if (!net) {
        return libmexclass::error::Error{
            "sq:datostim:badNet",
            std::string("No MexNetwork registered for handle ") +
            std::to_string(net_handle) +
            ". Pass net.networkHandle() to DatostimWindow."};
    }

    // Normalize path (resolve any ".." components) before LoadLibraryA.
    {
        char buf[MAX_PATH];
        if (GetFullPathNameA(dll_path.c_str(), MAX_PATH, buf, nullptr))
            dll_path = buf;
    }

    // Load datostim.dll.
    // LOAD_WITH_ALTERED_SEARCH_PATH makes Windows use datostim.dll's own
    // directory as the first location when resolving its dependencies
    // (libdatoviz.dll, libgcc_s_seh-1.dll, etc. that we copied alongside it).
    // Without this flag, LoadLibraryA uses the application (MATLAB) directory
    // and PATH — neither of which contains those DLLs.
    HMODULE dll = LoadLibraryExA(dll_path.c_str(), nullptr,
                                  LOAD_WITH_ALTERED_SEARCH_PATH);
    if (!dll) {
        DWORD err = GetLastError();
        return libmexclass::error::Error{
            "sq:datostim:dllNotFound",
            std::string("Failed to load datostim.dll (error ") +
            std::to_string(err) + "): " + dll_path};
    }

    // Bind function pointers.
    DatostimAPI api;
    api.init       = reinterpret_cast<DatostimAPI::init_t>   (GetProcAddress(dll, "dstim_init"));
    api.cleanup    = reinterpret_cast<DatostimAPI::cleanup_t> (GetProcAddress(dll, "dstim_cleanup"));
    api.background = reinterpret_cast<DatostimAPI::bg_t>      (GetProcAddress(dll, "dstim_background"));
    api.screen     = reinterpret_cast<DatostimAPI::screen_t>  (GetProcAddress(dll, "dstim_screen"));
    api.update     = reinterpret_cast<DatostimAPI::update_t>  (GetProcAddress(dll, "dstim_update"));
    api.time       = reinterpret_cast<DatostimAPI::time_t>    (GetProcAddress(dll, "dstim_time"));
    api.frame_time = reinterpret_cast<DatostimAPI::time_t>    (GetProcAddress(dll, "dstim_frame_time"));
    api.lyr_show   = reinterpret_cast<DatostimAPI::show_t>    (GetProcAddress(dll, "dstim_layer_show"));
    api.lyr_periodic=reinterpret_cast<DatostimAPI::per_t>     (GetProcAddress(dll, "dstim_layer_periodic"));
    api.lyr_blend  = reinterpret_cast<DatostimAPI::blend_t>   (GetProcAddress(dll, "dstim_layer_blend"));
    api.lyr_interp = reinterpret_cast<DatostimAPI::interp_t>  (GetProcAddress(dll, "dstim_layer_interpolation"));
    api.lyr_mask   = reinterpret_cast<DatostimAPI::mask_t>    (GetProcAddress(dll, "dstim_layer_mask"));
    api.lyr_min    = reinterpret_cast<DatostimAPI::color_t>   (GetProcAddress(dll, "dstim_layer_min_color"));
    api.lyr_max    = reinterpret_cast<DatostimAPI::color_t>   (GetProcAddress(dll, "dstim_layer_max_color"));
    api.lyr_angle  = reinterpret_cast<DatostimAPI::angle_t>   (GetProcAddress(dll, "dstim_layer_angle"));
    api.lyr_offset = reinterpret_cast<DatostimAPI::offset_t>  (GetProcAddress(dll, "dstim_layer_offset"));
    api.lyr_size   = reinterpret_cast<DatostimAPI::lsize_t>   (GetProcAddress(dll, "dstim_layer_size"));
    api.lyr_view   = reinterpret_cast<DatostimAPI::view_t>    (GetProcAddress(dll, "dstim_layer_view"));
    api.lyr_tex    = reinterpret_cast<DatostimAPI::texture_t> (GetProcAddress(dll, "dstim_layer_texture"));

    if (!api.init || !api.cleanup || !api.update || !api.lyr_show) {
        FreeLibrary(dll);
        return libmexclass::error::Error{
            "sq:datostim:badDll",
            "datostim.dll is missing required exports (dstim_init/update/cleanup/layer_show)"};
    }

    // Extract datostim directory from the normalized DLL path.
    // dstim_init (and later dstim_update, which lazily creates sphere pipelines)
    // loads shaders and data via relative paths ("shaders/*.spv", "data/vertex",
    // etc.).  When called from MATLAB, the CWD is MATLAB's pwd, not the datostim
    // directory.  We save/restore CWD around every datostim call that touches disk.
    std::string datostim_dir = dll_path;
    {
        auto last_sep = datostim_dir.find_last_of("\\/");
        if (last_sep != std::string::npos) datostim_dir.resize(last_sep);
    }

    char cwd_save[MAX_PATH] = {};
    GetCurrentDirectoryA(MAX_PATH, cwd_save);
    SetCurrentDirectoryA(datostim_dir.c_str());

    DStim* stim = api.init(width, height);

    SetCurrentDirectoryA(cwd_save);

    if (!stim) {
        FreeLibrary(dll);
        return libmexclass::error::Error{
            "sq:datostim:initFailed", "dstim_init returned NULL"};
    }

    return std::make_shared<DatostimProxy>(std::move(net), stim,
                                           static_cast<void*>(dll), api,
                                           std::move(datostim_dir));
}

// ---------------------------------------------------------------------------
// WatchLayer
// ---------------------------------------------------------------------------

void DatostimProxy::WatchLayer(libmexclass::proxy::method::Context& ctx) {
    if (ctx.inputs.getNumberOfElements() < 2) {
        ctx.error = libmexclass::error::Error{
            "sq:datostim:badArgs", "WatchLayer requires (layer_idx, node_id)"};
        return;
    }
    matlab::data::TypedArray<double> li = ctx.inputs[0];
    matlab::data::TypedArray<double> ni = ctx.inputs[1];
    watched_[static_cast<uint32_t>(double(li[0]))] = static_cast<long>(double(ni[0]));
}

// ---------------------------------------------------------------------------
// update_layer — parse MATLAB layer struct, push to datostim (no MATLAB call)
// ---------------------------------------------------------------------------

void DatostimProxy::update_layer(uint32_t idx, const matlab::data::Array& val) {
    using Traits = ValueTraits<matlab::data::Array>;
    if (!Traits::has_value(val)) return;

    matlab::data::StructArray sa = val;

    // --- visibility ---
    if (api_.lyr_show)
        api_.lyr_show(stim_, idx, field_bool(sa, "show", false));

    // --- periodic ---
    if (api_.lyr_periodic)
        api_.lyr_periodic(stim_, idx, field_bool(sa, "isPeriodic", true));

    // --- blending ---
    if (api_.lyr_blend) {
        const std::string b = field_string(sa, "blending");
        DStimBlend blend = DSTIM_BLEND_NONE;
        if (b == "dst"  || b == "destination")  blend = DSTIM_BLEND_DST;
        else if (b == "src"  || b == "source")  blend = DSTIM_BLEND_SRC;
        else if (b == "1-src"|| b == "1-source")blend = DSTIM_BLEND_ONE_MINUS_SRC;
        api_.lyr_blend(stim_, idx, blend);
    }

    // --- interpolation ---
    if (api_.lyr_interp) {
        const std::string s = field_string(sa, "interpolation");
        api_.lyr_interp(stim_, idx,
            s == "linear" ? DSTIM_INTERP_LINEAR : DSTIM_INTERP_NEAREST);
    }

    // --- colour mask (4×1 logical) ---
    if (api_.lyr_mask) {
        try {
            matlab::data::TypedArray<bool> cm = sa[0]["colourMask"];
            bool r = cm.getNumberOfElements() > 0 ? bool(cm[0]) : true;
            bool g = cm.getNumberOfElements() > 1 ? bool(cm[1]) : true;
            bool b = cm.getNumberOfElements() > 2 ? bool(cm[2]) : true;
            bool a = cm.getNumberOfElements() > 3 ? bool(cm[3]) : true;
            api_.lyr_mask(stim_, idx, r, g, b, a);
        } catch (...) {
            api_.lyr_mask(stim_, idx, true, true, true, true);
        }
    }

    // --- min / max colour (4×1 double, 0-1 → uint8 0-255) ---
    auto push_color = [&](const std::string& field, DatostimAPI::color_t fn) {
        if (!fn) return;
        try {
            matlab::data::TypedArray<double> c = sa[0][field];
            uint8_t r = c.getNumberOfElements() > 0 ? clamp_u8(double(c[0])) : 0;
            uint8_t g = c.getNumberOfElements() > 1 ? clamp_u8(double(c[1])) : 0;
            uint8_t b = c.getNumberOfElements() > 2 ? clamp_u8(double(c[2])) : 0;
            uint8_t a = c.getNumberOfElements() > 3 ? clamp_u8(double(c[3])) : 0;
            fn(stim_, idx, r, g, b, a);
        } catch (...) {}
    };
    push_color("minColour", api_.lyr_min);
    push_color("maxColour", api_.lyr_max);

    // --- texture angle (degrees → radians) ---
    if (api_.lyr_angle)
        api_.lyr_angle(stim_, idx, field_float(sa, "texAngle") * DEG2RAD);

    // --- texture offset (degrees, 2×1) ---
    if (api_.lyr_offset) {
        try {
            matlab::data::TypedArray<double> to = sa[0]["texOffset"];
            float x = to.getNumberOfElements() > 0 ? float(double(to[0])) : 0.0f;
            float y = to.getNumberOfElements() > 1 ? float(double(to[1])) : 0.0f;
            api_.lyr_offset(stim_, idx, x, y);
        } catch (...) {}
    }

    // --- texture size (degrees, 2×1) ---
    if (api_.lyr_size) {
        try {
            matlab::data::TypedArray<double> sz = sa[0]["size"];
            float w = sz.getNumberOfElements() > 0 ? float(double(sz[0])) : 0.0f;
            float h = sz.getNumberOfElements() > 1 ? float(double(sz[1])) : 0.0f;
            api_.lyr_size(stim_, idx, w, h);
        } catch (...) {}
    }

    // --- view matrix from pos[az, alt] and viewAngle (all in degrees) ---
    // Matches legacy convention: Rz(-az) * Ry(-alt) * Rx(viewAngle)
    if (api_.lyr_view) {
        float az = 0.0f, alt = 0.0f;
        try {
            matlab::data::TypedArray<double> pos = sa[0]["pos"];
            if (pos.getNumberOfElements() > 0) az  = float(double(pos[0]));
            if (pos.getNumberOfElements() > 1) alt = float(double(pos[1]));
        } catch (...) {}
        float view_angle = field_float(sa, "viewAngle");

        Mat4 rz, ry, rx, tmp, view;
        mat4_rot_z(-az  * DEG2RAD, rz);
        mat4_rot_y(-alt * DEG2RAD, ry);
        mat4_rot_x(view_angle * DEG2RAD, rx);
        mat4_mul(rz, ry, tmp);
        mat4_mul(tmp, rx, view);
        api_.lyr_view(stim_, idx, view);
    }

    // --- texture data (rgba uint8 column vector + rgbaSize [m,n]) ---
    if (api_.lyr_tex) {
        try {
            matlab::data::Array rgba_raw = sa[0]["rgba"];
            matlab::data::TypedArray<double> sz = sa[0]["rgbaSize"];
            if (!rgba_raw.isEmpty() && sz.getNumberOfElements() >= 2) {
                uint32_t tw = static_cast<uint32_t>(double(sz[0]));
                uint32_t th = static_cast<uint32_t>(double(sz[1]));
                matlab::data::TypedArray<uint8_t> rgba = rgba_raw;
                std::vector<uint8_t> buf(rgba.begin(), rgba.end());
                api_.lyr_tex(stim_, idx, DSTIM_FMT_RGBA8,
                             tw, th, static_cast<DvzSize>(buf.size()), buf.data());
            }
        } catch (...) {}
    }
}

// ---------------------------------------------------------------------------
// Draw
// ---------------------------------------------------------------------------

void DatostimProxy::Draw(libmexclass::proxy::method::Context& ctx) {
    if (!stim_ || crashed_) {
        ctx.error = libmexclass::error::Error{
            "sq:datostim:closed",
            "DatostimProxy has been cleaned up or has crashed"};
        return;
    }

    // Push layer data to datostim (simple struct-field setters; no GPU work).
    for (auto& [layer_idx, node_id] : watched_)
        update_layer(layer_idx, net_->get_current_value(node_id));

    if (!api_.update) return;

    // Protect the GPU submission path with a SIGABRT interceptor.
    // dvz_assert() calls abort() when an internal invariant fails.  Without
    // this guard, that abort() kills the entire MATLAB process.  With it, the
    // failure surfaces as a MATLAB error and the window is marked invalid.
    auto prev_handler = signal(SIGABRT, abort_interception);
    tls_abort_armed   = true;
    char cwd_save[MAX_PATH] = {};
    GetCurrentDirectoryA(MAX_PATH, cwd_save);
    SetCurrentDirectoryA(datostim_dir_.c_str());

    if (setjmp(tls_abort_env) != 0) {
        // datoviz called abort() — renderer state is corrupted.
        // Do NOT call dstim_cleanup or FreeLibrary: datoviz background threads
        // may still be running; unloading the DLL would cause a use-after-free.
        SetCurrentDirectoryA(cwd_save);
        signal(SIGABRT, prev_handler);
        crashed_ = true;
        stim_    = nullptr;
        ctx.error = libmexclass::error::Error{
            "sq:datostim:aborted",
            "datoviz assertion failed; window is now invalid — call cleanup()"};
        return;
    }

    // Non-blocking rate cap: skip GPU submission if called faster than ~120fps.
    // datoviz's internal event FIFO overflows when dvz_app_submit is called
    // faster than the renderer can consume frames.  dvz_app_wait (frame_time)
    // would be the correct sync primitive but it blocks forever when there is
    // no background event loop (our usage model: submit-only, no dvz_app_run).
    auto now = std::chrono::steady_clock::now();
    auto elapsed_us = std::chrono::duration_cast<std::chrono::microseconds>(
        now - last_draw_).count();
    if (elapsed_us < 8333) {  // < ~8.3 ms → above 120fps → skip
        tls_abort_armed = false;
        SetCurrentDirectoryA(cwd_save);
        signal(SIGABRT, prev_handler);
        return;
    }
    last_draw_ = now;

    // Submit the new frame.
    api_.update(stim_);

    tls_abort_armed = false;
    SetCurrentDirectoryA(cwd_save);
    signal(SIGABRT, prev_handler);
}

// ---------------------------------------------------------------------------
// SetBackground
// ---------------------------------------------------------------------------

void DatostimProxy::SetBackground(libmexclass::proxy::method::Context& ctx) {
    if (!api_.background || ctx.inputs.getNumberOfElements() < 4) {
        ctx.error = libmexclass::error::Error{
            "sq:datostim:badArgs", "SetBackground requires (r, g, b, a) as 0-255 doubles"};
        return;
    }
    auto u8 = [&](int i) -> uint8_t {
        matlab::data::TypedArray<double> a = ctx.inputs[i];
        return static_cast<uint8_t>(std::max(0.0, std::min(255.0, double(a[0]))));
    };
    api_.background(stim_, u8(0), u8(1), u8(2), u8(3));
}

// ---------------------------------------------------------------------------
// SetScreen
// ---------------------------------------------------------------------------

void DatostimProxy::SetScreen(libmexclass::proxy::method::Context& ctx) {
    if (!api_.screen || ctx.inputs.getNumberOfElements() < 5) {
        ctx.error = libmexclass::error::Error{
            "sq:datostim:badArgs", "SetScreen requires (screen_idx, x, y, w, h)"};
        return;
    }
    auto u32 = [&](int i) -> uint32_t {
        matlab::data::TypedArray<double> a = ctx.inputs[i];
        return static_cast<uint32_t>(double(a[0]));
    };
    api_.screen(stim_, u32(0), u32(1), u32(2), u32(3), u32(4));
}

// ---------------------------------------------------------------------------
// GetTime
// ---------------------------------------------------------------------------

void DatostimProxy::GetTime(libmexclass::proxy::method::Context& ctx) {
    matlab::data::ArrayFactory f;
    ctx.outputs[0] = f.createScalar<double>(
        (api_.time && stim_) ? api_.time(stim_) : 0.0);
}

// ---------------------------------------------------------------------------
// Cleanup
// ---------------------------------------------------------------------------

void DatostimProxy::Cleanup(libmexclass::proxy::method::Context& ctx) {
    if (stim_ && api_.cleanup) {
        api_.cleanup(stim_);
        stim_ = nullptr;
    }
}

} // namespace sq::proxy
