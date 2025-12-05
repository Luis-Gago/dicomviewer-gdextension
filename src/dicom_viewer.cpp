#include "dicom_viewer.h"

#ifdef USE_DCMTK
#include <dcmtk/dcmimgle/dcmimage.h>
#include <dcmtk/dcmdata/dctk.h>
#include <dcmtk/ofstd/ofstd.h>
#include <dcmtk/ofstd/ofstring.h>
// Add these headers for decompression support
#include <dcmtk/dcmjpeg/djdecode.h>  // JPEG decoders
#include <dcmtk/dcmjpls/djdecode.h>  // JPEG-LS decoders  
#include <dcmtk/dcmdata/dcrledrg.h>  // RLE decoder
#endif

#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

#ifdef USE_DCMTK
// Static flag to ensure we only register codecs once
static bool dcmtk_codecs_registered = false;

static void register_dcmtk_codecs() {
    if (!dcmtk_codecs_registered) {
        // Register JPEG decompression codecs
        DJDecoderRegistration::registerCodecs();
        // Register JPEG-LS decompression codecs
        DJLSDecoderRegistration::registerCodecs();
        // Register RLE decompression codec
        DcmRLEDecoderRegistration::registerCodecs();
        
        dcmtk_codecs_registered = true;
        UtilityFunctions::print("DCMTK decompression codecs registered");
    }
}
#endif

void DicomViewer::_bind_methods() {
    ClassDB::bind_method(D_METHOD("load_dicom", "path"), &DicomViewer::load_dicom);
    ClassDB::bind_method(D_METHOD("set_window_level", "window", "level"), &DicomViewer::set_window_level);
    ClassDB::bind_method(D_METHOD("set_window", "window"), &DicomViewer::set_window);
    ClassDB::bind_method(D_METHOD("set_level", "level"), &DicomViewer::set_level);
    ClassDB::bind_method(D_METHOD("get_window"), &DicomViewer::get_window);
    ClassDB::bind_method(D_METHOD("get_level"), &DicomViewer::get_level);
    ClassDB::bind_method(D_METHOD("zoom_in"), &DicomViewer::zoom_in);
    ClassDB::bind_method(D_METHOD("zoom_out"), &DicomViewer::zoom_out);
    ClassDB::bind_method(D_METHOD("reset_view"), &DicomViewer::reset_view);
    ClassDB::bind_method(D_METHOD("get_metadata"), &DicomViewer::get_metadata);
    // Add preset window/level methods
    ClassDB::bind_method(D_METHOD("apply_soft_tissue_preset"), &DicomViewer::apply_soft_tissue_preset);
    ClassDB::bind_method(D_METHOD("apply_lung_preset"), &DicomViewer::apply_lung_preset);
    ClassDB::bind_method(D_METHOD("apply_bone_preset"), &DicomViewer::apply_bone_preset);
    // Remove the _gui_input binding - it's a virtual override

    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "window"), "set_window", "get_window");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "level"), "set_level", "get_level");
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
    // Register decompression codecs first
    register_dcmtk_codecs();
    
    // Load file and dataset
    DcmFileFormat file;
    OFCondition loadStatus = file.loadFile(path.utf8().get_data());
    if (!loadStatus.good()) {
        UtilityFunctions::printerr("DCMTK Error loading file: ", loadStatus.text());
        return false;
    }
    DcmDataset *ds = file.getDataset();
    if (!ds) {
        UtilityFunctions::printerr("DCMTK Error: No dataset found");
        return false;
    }

    // Print some diagnostic info about the image
    OFString transferSyntax;
    if (ds->findAndGetOFString(DCM_TransferSyntaxUID, transferSyntax).good()) {
        UtilityFunctions::print("Transfer Syntax: ", transferSyntax.c_str());
    } else {
        UtilityFunctions::print("Transfer Syntax: Not found (assuming Implicit VR Little Endian)");
    }
    
    OFString photometricInterpretation;
    if (ds->findAndGetOFString(DCM_PhotometricInterpretation, photometricInterpretation).good()) {
        UtilityFunctions::print("Photometric Interpretation: ", photometricInterpretation.c_str());
    }

    // Read image dimensions
    Uint16 rows = 0, cols = 0;
    if (!ds->findAndGetUint16(DCM_Rows, rows).good() || !ds->findAndGetUint16(DCM_Columns, cols).good()) {
        UtilityFunctions::printerr("DCMTK Error: Missing image dimensions (Rows/Columns)");
        return false;
    }
    
    if (rows == 0 || cols == 0) {
        UtilityFunctions::printerr("DCMTK Error: Invalid dimensions: ", cols, "x", rows);
        return false;
    }

    UtilityFunctions::print("Image dimensions: ", cols, "x", rows);

    // Read some metadata values
    OFString ofstr;
    double rescale_slope = 1.0;
    double rescale_intercept = 0.0;
    Uint16 pixel_representation = 0;
    Uint16 bits_allocated = 16;
    Uint16 bits_stored = 12;
    Uint16 high_bit = 15;
    double voi_center = 0.0;
    double voi_width = 0.0;
    bool have_voi = false;

    ds->findAndGetUint16(DCM_BitsAllocated, bits_allocated);
    ds->findAndGetUint16(DCM_BitsStored, bits_stored);
    ds->findAndGetUint16(DCM_HighBit, high_bit);
    ds->findAndGetUint16(DCM_PixelRepresentation, pixel_representation);

    if (ds->findAndGetOFString(DCM_RescaleSlope, ofstr).good()) {
        rescale_slope = atof(ofstr.c_str());
        UtilityFunctions::print("Rescale Slope: ", rescale_slope);
    }
    if (ds->findAndGetOFString(DCM_RescaleIntercept, ofstr).good()) {
        rescale_intercept = atof(ofstr.c_str());
        UtilityFunctions::print("Rescale Intercept: ", rescale_intercept);
    }
    
    // WindowCenter and WindowWidth can have multiple values (multiple presets)
    // We'll take the first value
    if (ds->findAndGetOFString(DCM_WindowCenter, ofstr, 0).good()) {
        voi_center = atof(ofstr.c_str());
        have_voi = true;
        UtilityFunctions::print("Window Center (VOI): ", voi_center);
    }
    if (ds->findAndGetOFString(DCM_WindowWidth, ofstr, 0).good()) {
        voi_width = atof(ofstr.c_str());
        UtilityFunctions::print("Window Width (VOI): ", voi_width);
    }

    UtilityFunctions::print("Bits Allocated/Stored: ", bits_allocated, "/", bits_stored, 
                           ", Pixel Representation: ", pixel_representation);

    // Use DicomImage - with codecs registered, it should handle decompression
    DicomImage dcm_image(path.utf8().get_data());
    
    EI_Status status = dcm_image.getStatus();
    if (status != EIS_Normal) {
        UtilityFunctions::printerr("DCMTK DicomImage Error (status ", (int)status, "): ", 
                                  DicomImage::getString(status));
        return false;
    }
    
    const int w = dcm_image.getWidth();
    const int h = dcm_image.getHeight();
    
    UtilityFunctions::print("Successfully loaded DICOM image via DicomImage: ", w, "x", h);

    // Get min/max values from DicomImage (these are already rescaled)
    double minValue = 0.0;
    double maxValue = 0.0;
    if (dcm_image.getMinMaxValues(minValue, maxValue) > 0) {
        UtilityFunctions::print("DicomImage reports min/max: ", minValue, " to ", maxValue);
    }

    raw_pixels.assign((size_t)w * (size_t)h, 0.0);
    raw_width = w;
    raw_height = h;

    // Get internal pixel data which has modality LUT applied (rescale slope/intercept)
    const DiPixel* pixelData = dcm_image.getInterData();
    if (!pixelData) {
        UtilityFunctions::printerr("DCMTK Error: Failed to get internal pixel data");
        return false;
    }

    // Get the representation (might be different from original)
    EP_Representation pixelRep = pixelData->getRepresentation();
    const void* dataPtr = pixelData->getData();
    
    if (!dataPtr) {
        UtilityFunctions::printerr("DCMTK Error: Internal pixel data pointer is null");
        return false;
    }

    double computed_min = 0.0, computed_max = 0.0;
    bool first = true;

    // Read based on actual internal representation
    if (pixelRep == EPR_Sint16) {
        const Sint16* pixels = static_cast<const Sint16*>(dataPtr);
        for (int i = 0; i < w * h; ++i) {
            double val = static_cast<double>(pixels[i]);
            raw_pixels[i] = val;
            
            if (first) {
                computed_min = computed_max = val;
                first = false;
            } else {
                if (val < computed_min) computed_min = val;
                if (val > computed_max) computed_max = val;
            }
        }
    } else if (pixelRep == EPR_Uint16) {
        const Uint16* pixels = static_cast<const Uint16*>(dataPtr);
        for (int i = 0; i < w * h; ++i) {
            double val = static_cast<double>(pixels[i]);
            raw_pixels[i] = val;
            
            if (first) {
                computed_min = computed_max = val;
                first = false;
            } else {
                if (val < computed_min) computed_min = val;
                if (val > computed_max) computed_max = val;
            }
        }
    } else if (pixelRep == EPR_Sint32) {
        const Sint32* pixels = static_cast<const Sint32*>(dataPtr);
        for (int i = 0; i < w * h; ++i) {
            double val = static_cast<double>(pixels[i]);
            raw_pixels[i] = val;
            
            if (first) {
                computed_min = computed_max = val;
                first = false;
            } else {
                if (val < computed_min) computed_min = val;
                if (val > computed_max) computed_max = val;
            }
        }
    } else if (pixelRep == EPR_Uint32) {
        const Uint32* pixels = static_cast<const Uint32*>(dataPtr);
        for (int i = 0; i < w * h; ++i) {
            double val = static_cast<double>(pixels[i]);
            raw_pixels[i] = val;
            
            if (first) {
                computed_min = computed_max = val;
                first = false;
            } else {
                if (val < computed_min) computed_min = val;
                if (val > computed_max) computed_max = val;
            }
        }
    } else {
        UtilityFunctions::printerr("DCMTK Error: Unsupported pixel representation: ", (int)pixelRep);
        return false;
    }

    UtilityFunctions::print("Computed pixel value range: ", computed_min, " to ", computed_max);

    // If VOI WindowCenter/Width available, use them as defaults
    if (have_voi && voi_width > 0.0) {
        window_center = static_cast<float>(voi_center);
        window_width = static_cast<float>(voi_width);
        UtilityFunctions::print("Using DICOM VOI Window/Level: ", window_width, " / ", window_center);
    } else {
        // Otherwise pick a sensible default from actual data range
        window_center = static_cast<float>((computed_min + computed_max) * 0.5);
        window_width = static_cast<float>((computed_max - computed_min));
        if (window_width <= 0.0f) window_width = 1.0f;
        UtilityFunctions::print("No VOI metadata, using calculated Window/Level: ", window_width, " / ", window_center);
    }

#else
    // Fallback: try to load as a regular image via Image::load_from_file
    Ref<Image> tmp = Image::load_from_file(path);
    if (tmp.is_null()) {
        return false;
    }

    if (tmp->get_format() != Image::FORMAT_L8) {
        tmp->convert(Image::FORMAT_L8);
    }

    PackedByteArray data = tmp->get_data();
    int w = tmp->get_width();
    int h = tmp->get_height();

    raw_pixels.assign(w * h, 0.0);
    const uint8_t *ptr = data.ptr();
    for (int i = 0; i < w * h; ++i) {
        raw_pixels[i] = static_cast<double>(ptr[i]);
    }
    raw_width = w;
    raw_height = h;

    window_center = 127.5f;
    window_width = 255.0f;
#endif

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

    image_data = Image::create_from_data(raw_width, raw_height, false, Image::FORMAT_L8, bytes);
}

void DicomViewer::update_texture() {
    if (image_data.is_null()) {
        return;
    }

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
    meta["note"] = "DCMTK built-in; metadata available during load_dicom()";
#else
    meta["note"] = "No DICOM library compiled; metadata unavailable";
#endif
    return meta;
}


void DicomViewer::apply_soft_tissue_preset() {
    set_window_level(400.0f, 40.0f);
}

void DicomViewer::apply_lung_preset() {
    set_window_level(1500.0f, -600.0f);
}

void DicomViewer::apply_bone_preset() {
    set_window_level(1800.0f, 400.0f);
}