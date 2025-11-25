#pragma once

#include <godot_cpp/classes/control.hpp>
#include <godot_cpp/classes/texture_rect.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/core/gdvirtual.gen.inc>
#include <vector>

using namespace godot;

class DicomViewer : public Control {
    GDCLASS(DicomViewer, Control);

    TextureRect *texture_rect;
    Ref<ImageTexture> image_texture;
    Ref<Image> image_data;

    // Raw pixel storage for fast window/level remapping (physical values)
    std::vector<double> raw_pixels;
    int raw_width;
    int raw_height;

    float window_width;
    float window_center;
    float zoom;
    Vector2 pan;

protected:
    static void _bind_methods();

public:
    DicomViewer();

    // Load a DICOM file (or a normal image if no DICOM library is available)
    bool load_dicom(const String &path);

    // Simple pixel window/level adjustment (affects how we map pixel values to 8-bit)
    void set_window_level(float window, float level);
    float get_window() const { return window_width; }
    float get_level() const { return window_center; }
    void set_window(float window) { set_window_level(window, window_center); }
    void set_level(float level) { set_window_level(window_width, level); }

    // Zoom / pan helpers
    void zoom_in();
    void zoom_out();
    void reset_view();

    // Returns a dictionary of parsed metadata (if available)
    Dictionary get_metadata() const;

    // Utility to update the displayed texture from internal Image
    void update_texture();

    // Map raw pixels through window/level into the Image
    void apply_window_level();
};