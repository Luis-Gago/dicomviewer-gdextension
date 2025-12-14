#pragma once

#include <godot_cpp/classes/control.hpp>
#include <godot_cpp/classes/texture_rect.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/image.hpp>
#include <vector>

namespace godot {

class DicomViewer : public Control {
    GDCLASS(DicomViewer, Control);

private:
    TextureRect *texture_rect;
    Ref<ImageTexture> image_texture;
    Ref<Image> image_data;

    std::vector<double> raw_pixels;
    int raw_width;
    int raw_height;

    float window_width;
    float window_center;
    float zoom;
    Vector2 pan;
    float pixel_aspect_ratio;
    
    String current_modality;
    
    // Store original DICOM VOI values
    float original_window_width;
    float original_window_center;
    bool has_original_voi;
    
    void apply_window_level();
    void update_texture();

protected:
    static void _bind_methods();

public:
    DicomViewer();
    ~DicomViewer() {}

    bool load_dicom(const String &path);
    void set_window_level(float window, float level);
    void set_window(float window) { window_width = window; apply_window_level(); update_texture(); }
    void set_level(float level) { window_center = level; apply_window_level(); update_texture(); }
    float get_window() const { return window_width; }
    float get_level() const { return window_center; }

    void zoom_in();
    void zoom_out();
    void reset_view();
    
    Dictionary get_metadata() const;
    float get_pixel_aspect_ratio() const { return pixel_aspect_ratio; }
    String get_modality() const { return current_modality; }
    
    // Window/Level presets
    void apply_soft_tissue_preset();
    void apply_lung_preset();
    void apply_bone_preset();
    void apply_brain_preset();
    void apply_t2_brain_preset();
    void apply_mammography_preset();
    void apply_auto_preset();
    void apply_modality_preset();  // Auto-select based on modality
};

}