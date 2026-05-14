#pragma once

#include "libmexclass/proxy/Proxy.h"
#include "libmexclass/proxy/method/Context.h"
#include "mex_network.h"

#include <chrono>
#include <memory>
#include <unordered_map>
#include <cstdint>

// Opaque — DStim* is used only as a pointer; the actual struct lives in datostim.dll.
struct DStim;

namespace sq::proxy {

// ---------------------------------------------------------------------------
// Minimal type aliases matching datostim.h / datoviz_enums.h.
// Defined here so DatostimProxy.cpp never needs to include datoviz headers.
// DVZ_FORMAT_R8G8B8A8_UNORM = 37 is fixed by the Vulkan spec and verified in
// extern/datoviz/include/datoviz_enums.h.
// ---------------------------------------------------------------------------

using DvzSize   = uint64_t;
using DvzFormat = int;
static constexpr DvzFormat DSTIM_FMT_RGBA8 = 37;

enum DStimInterpolation { DSTIM_INTERP_NEAREST = 0, DSTIM_INTERP_LINEAR = 1 };

enum DStimBlend {
    DSTIM_BLEND_NONE = 0,
    DSTIM_BLEND_DST,
    DSTIM_BLEND_SRC,
    DSTIM_BLEND_ONE_MINUS_SRC,
};

// ---------------------------------------------------------------------------
// Function pointer table loaded at runtime from datostim.dll.
// Keeping this as a plain struct (not a class with virtual dispatch) so that
// the hot path in Draw() pays only one indirect call per dstim_* call.
// ---------------------------------------------------------------------------

struct DatostimAPI {
    using init_t    = DStim* (*)(uint32_t w, uint32_t h);
    using cleanup_t = void   (*)(DStim*);
    using bg_t      = void   (*)(DStim*, uint8_t, uint8_t, uint8_t, uint8_t);
    using screen_t  = void   (*)(DStim*, uint32_t idx, uint32_t x, uint32_t y,
                                          uint32_t w, uint32_t h);
    using update_t  = void   (*)(DStim*);
    using time_t    = double (*)(DStim*);
    using show_t    = void   (*)(DStim*, uint32_t, bool);
    using per_t     = void   (*)(DStim*, uint32_t, bool);
    using blend_t   = void   (*)(DStim*, uint32_t, DStimBlend);
    using interp_t  = void   (*)(DStim*, uint32_t, DStimInterpolation);
    using mask_t    = void   (*)(DStim*, uint32_t, bool, bool, bool, bool);
    using color_t   = void   (*)(DStim*, uint32_t, uint8_t, uint8_t, uint8_t, uint8_t);
    using angle_t   = void   (*)(DStim*, uint32_t, float);
    using offset_t  = void   (*)(DStim*, uint32_t, float, float);
    using lsize_t   = void   (*)(DStim*, uint32_t, float, float);
    using view_t    = void   (*)(DStim*, uint32_t, float (*view)[4]);
    using texture_t = void   (*)(DStim*, uint32_t, DvzFormat,
                                          uint32_t w, uint32_t h,
                                          DvzSize nbytes, uint8_t* rgba);

    init_t    init       = nullptr;
    cleanup_t cleanup    = nullptr;
    bg_t      background = nullptr;
    screen_t  screen     = nullptr;
    update_t  update     = nullptr;
    time_t    time       = nullptr;
    time_t    frame_time = nullptr;  // dstim_frame_time: dvz_app_wait + timestamp
    show_t    lyr_show   = nullptr;
    per_t     lyr_periodic = nullptr;
    blend_t   lyr_blend  = nullptr;
    interp_t  lyr_interp = nullptr;
    mask_t    lyr_mask   = nullptr;
    color_t   lyr_min    = nullptr;
    color_t   lyr_max    = nullptr;
    angle_t   lyr_angle  = nullptr;
    offset_t  lyr_offset = nullptr;
    lsize_t   lyr_size   = nullptr;
    view_t    lyr_view   = nullptr;
    texture_t lyr_tex    = nullptr;
};

// ---------------------------------------------------------------------------
// DatostimProxy
// ---------------------------------------------------------------------------

/// MEX proxy that drives a datostim window directly from MexNetwork node values,
/// bypassing MATLAB entirely in the hot draw path.
///
/// Construction from MATLAB:
///   proxy = libmexclass.proxy.Proxy("Name", "sig.DatostimProxy",
///     "ConstructorArguments", {net_proxy_id, width, height, dll_path})
///
///   net_proxy_id — uint64 libmexclass ID of the NetworkProxy (net.networkProxyId()).
///   dll_path     — full path to datostim.dll built by extern/datostim/build.ps1.
class DatostimProxy : public libmexclass::proxy::Proxy {
  public:
    DatostimProxy(std::shared_ptr<MexNetwork> net,
                  DStim* stim, void* dll_handle, DatostimAPI api,
                  std::string datostim_dir);
    ~DatostimProxy();

    static libmexclass::proxy::MakeResult make(
        const libmexclass::proxy::FunctionArguments& constructor_arguments);

    // Register node_id as the data source for layer layer_idx (0-based).
    void WatchLayer  (libmexclass::proxy::method::Context& ctx);

    // Read all watched nodes, push layer params to datostim, call dstim_update.
    void Draw        (libmexclass::proxy::method::Context& ctx);

    // Set window background colour (r g b a as doubles 0-255).
    void SetBackground(libmexclass::proxy::method::Context& ctx);

    // Configure one screen region: (screen_idx, x, y, w, h as doubles).
    void SetScreen   (libmexclass::proxy::method::Context& ctx);

    // Return dstim_time() as a double scalar.
    void GetTime     (libmexclass::proxy::method::Context& ctx);

    // Destroy the datostim window and free the DLL handle.
    void Cleanup     (libmexclass::proxy::method::Context& ctx);

  private:
    std::shared_ptr<MexNetwork> net_;
    DStim*       stim_       = nullptr;
    void*        dll_handle_ = nullptr;  // HMODULE on Windows
    DatostimAPI  api_;
    std::string  datostim_dir_;  // directory containing datostim.dll (for CWD restore)
    bool         crashed_ = false;
    std::chrono::steady_clock::time_point last_draw_{};

    std::unordered_map<uint32_t, long> watched_;  // layer_idx → node_id

    void update_layer(uint32_t layer_idx, const matlab::data::Array& val);
};

} // namespace sq::proxy
