#include "dicom_viewer.h"

#ifdef USE_DCMTK
#include <dcmtk/dcmimgle/dcmimage.h>
#include <dcmtk/dcmdata/dctk.h>
#include <dcmtk/ofstd/ofstd.h>
#include <dcmtk/ofstd/ofstring.h>
#endif

#include <godot_cpp/variant/packed_byte_array.hpp>

using namespace godot;

void DicomViewer::_bind_methods() {
    ClassDB::bind_method(D_METHOD("load_dicom", "path"), &DicomViewer::load_dicom);
    ClassDB::bind_method(D_METHOD("set_window_level", "window", "level"), &DicomViewer::set_window_level);
    ClassDB::bind_method(D_METHOD("get_window"), &DicomViewer::get_window);
    ClassDB::bind_method(D_METHOD("get_level"), &DicomViewer::get_level);
    ClassDB::bind_method(D_METHOD("zoom_in"), &DicomViewer::zoom_in);
    ClassDB::bind_method(D_METHOD("zoom_out"), &DicomViewer::zoom_out);
    ClassDB::bind_method(D_METHOD("reset_view"), &DicomViewer::reset_view);
    ClassDB::bind_method(D_METHOD("get_metadata"), &DicomViewer::get_metadata);

    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "window"), "set_window_level", "get_window");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "level"), "set_window_level", "get_level");
}

DicomViewer::DicomViewer() {
    texture_rect = memnew(TextureRect);
    add_child(texture_rect);
    texture_rect->set_anchors_preset(PRESET_FULL_RECT);

    image_texture = Ref<ImageTexture>();
    image_data = Ref<Image>();

    window_width = 400.0f;
    window_center = 40.0f;
    zoom = 1.0f;
    pan = Vector2(0,0);

    raw_width = raw_height = 0;
}

bool DicomViewer::load_dicom(const String &path) {

#ifdef USE_DCMTK
    // Load file and dataset
    DcmFileFormat file;
    OFCondition loadStatus = file.loadFile(path.utf8().get_data());
    if (!loadStatus.good()) {
        return false;
    }
    DcmDataset *ds = file.getDataset();
    if (!ds) {
        return false;
    }

    // Read some metadata values (Rescale Slope/Intercept, WindowCenter/Width, PixelRepresentation)
    OFString ofstr;
    double rescale_slope = 1.0;
    double rescale_intercept = 0.0;
    int pixel_representation = 0; // 0 = unsigned, 1 = signed
    double voi_center = 0.0;
    double voi_width = 0.0;
    bool have_voi = false;

    if (ds->findAndGetOFString(DCM_RescaleSlope, ofstr).good()) {
        rescale_slope = atof(ofstr.c_str());
    }
    if (ds->findAndGetOFString(DCM_RescaleIntercept, ofstr).good()) {
        rescale_intercept = atof(ofstr.c_str());
    }
    if (ds->findAndGetOFString(DCM_PixelRepresentation, ofstr).good()) {
        pixel_representation = atoi(ofstr.c_str());
    }
    if (ds->findAndGetOFString(DCM_WindowCenter, ofstr).good()) {
        voi_center = atof(ofstr.c_str());
        have_voi = true;
    }
    if (ds->findAndGetOFString(DCM_WindowWidth, ofstr).good()) {
        voi_width = atof(ofstr.c_str());
        have_voi = true;
    }

    // Use DicomImage to decode pixels (request 16-bit output for full fidelity)
    DicomImage dcm_image(path.utf8().get_data());
    if (dcm_image.getStatus() != EIS_Normal) {
        return false;
    }

    const int w = dcm_image.getWidth();
    const int h = dcm_image.getHeight();
    const int frame = 0;
    const int bits = 16; // request 16-bit output to preserve precision
    const void *pixel_ptr = dcm_image.getOutputData(bits, frame);
    if (!pixel_ptr) {
        return false;
    }

    raw_pixels.assign((size_t)w * (size_t)h, 0.0);
    raw_width = w;
    raw_height = h;

    // Determine whether data should be interpreted as signed or unsigned
    // PixelRepresentation tag in dataset indicates stored format (0 unsigned, 1 signed)
    // DCMTK getOutputData for 16 bits provides unsigned shorts in memory; if PixelRepresentation == 1
    // we reinterpret as int16_t.
    if (pixel_representation == 1) {
        const int16_t *src_s = static_cast<const int16_t*>(pixel_ptr);
        for (int i = 0; i < w * h; ++i) {
            double phys = static_cast<double>(src_s[i]) * rescale_slope + rescale_intercept;
            raw_pixels[i] = phys;
        }
    } else {
        const uint16_t *src_u = static_cast<const uint16_t*>(pixel_ptr);
        for (int i = 0; i < w * h; ++i) {
            double phys = static_cast<double>(src_u[i]) * rescale_slope + rescale_intercept;
            raw_pixels[i] = phys;
        }
    }

    // If VOI WindowCenter/Width available, use them as defaults
    if (have_voi) {
        window_center = static_cast<float>(voi_center);
        window_width = static_cast<float>(voi_width);
    } else {
        // Otherwise pick a sensible default from actual data range
        double minv = raw_pixels[0], maxv = raw_pixels[0];
        for (size_t i = 1; i < raw_pixels.size(); ++i) {
            if (raw_pixels[i] < minv) minv = raw_pixels[i];
            if (raw_pixels[i] > maxv) maxv = raw_pixels[i];
        }
        window_center = static_cast<float>((minv + maxv) * 0.5);
        window_width = static_cast<float>((maxv - minv));
        if (window_width <= 0.0f) window_width = 1.0f;
    }

#else
    // Fallback: try to load as a regular image via Image::load_from_file (returns Ref<Image>)
    Ref<Image> tmp = Image::load_from_file(path);
    if (tmp.is_null()) {
        return false;
    }

    // Ensure L8 for simpler mapping
    if (tmp->get_format() != Image::FORMAT_L8) {
        tmp->convert(Image::FORMAT_L8);
    }

    PackedByteArray data = tmp->get_data();
    int w = tmp->get_width();
    int h = tmp->get_height();

    raw_pixels.assign(w * h, 0.0);
    const uint8_t *ptr = data.ptr();
    for (int i = 0; i < w * h; ++i) {
        // For fallback images we treat stored byte as physical value 0..255
        raw_pixels[i] = static_cast<double>(ptr[i]);
    }
    raw_width = w;
    raw_height = h;

    // default window center/width
    window_center = 127.5f;
    window_width = 255.0f;
#endif

    // Apply initial window/level mapping and update texture
    apply_window_level();
    update_texture();

    return true;
}

void DicomViewer::apply_window_level() {
    if (raw_pixels.empty() || raw_width <= 0 || raw_height <= 0) {
        return;
    }

    PackedByteArray bytes;
    const size_t total = size_t(raw_width) * size_t(raw_height);
    bytes.resize((int)total);
    uint8_t *dst = bytes.ptrw();

    double low = static_cast<double>(window_center) - (static_cast<double>(window_width) * 0.5);
    double high = static_cast<double>(window_center) + (static_cast<double>(window_width) * 0.5);
    double denom = (high - low);
    if (denom <= 0.0) denom = 1.0;

    for (size_t i = 0; i < total; ++i) {
        double v = raw_pixels[i];
        double mapped = (v - low) * 255.0 / denom;
        if (mapped < 0.0) mapped = 0.0;
        if (mapped > 255.0) mapped = 255.0;
        dst[i] = uint8_t(mapped);
    }

    // Create a Ref<Image> from the L8 bytes and store in image_data
    image_data = Image::create_from_data(raw_width, raw_height, false, Image::FORMAT_L8, bytes);
}

void DicomViewer::update_texture() {
    if (image_data.is_null()) {
        return;
    }

    // Create or replace the ImageTexture from the Ref<Image>
    image_texture = ImageTexture::create_from_image(image_data);
    texture_rect->set_texture(image_texture);
}

void DicomViewer::set_window_level(float window, float level) {
    window_width = window;
    window_center = level;
    apply_window_level();
    update_texture();
}

void DicomViewer::zoom_in() {
    zoom *= 1.25f;
    texture_rect->set_scale(Size2(zoom, zoom));
}

void DicomViewer::zoom_out() {
    zoom /= 1.25f;
    texture_rect->set_scale(Size2(zoom, zoom));
}

void DicomViewer::reset_view() {
    zoom = 1.0f;
    pan = Vector2(0,0);
    texture_rect->set_scale(Size2(1,1));
    texture_rect->set_position(Vector2(0,0));
}

Dictionary DicomViewer::get_metadata() const {
    Dictionary meta;
#ifdef USE_DCMTK
    // Try to extract a few useful tags
    DcmFileFormat file;
    OFCondition loadStatus = file.loadFile(""); // placeholder; we cannot re-open without path here
    // We cannot reopen dataset because this method is const and we don't store the dataset.
    // For now return a simple flag. If you want persistent metadata access, store parsed tags when loading.
    meta["note"] = "DCMTK built-in; metadata available during load_dicom()";
#else
    meta["note"] = "No DICOM library compiled; metadata unavailable";
#endif
    return meta;
}