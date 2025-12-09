#pragma once

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

using namespace godot;

class RadiologyCase : public Resource {
    GDCLASS(RadiologyCase, Resource);

protected:
    static void _bind_methods();

private:
    String case_name;
    String case_description;
    Array dicom_file_paths;  // Array of Strings
    Array questions;  // Array of Dictionaries

public:
    RadiologyCase();

    void set_case_name(const String &p_name);
    String get_case_name() const;

    void set_case_description(const String &p_desc);
    String get_case_description() const;

    void set_dicom_file_paths(const Array &p_paths);
    Array get_dicom_file_paths() const;

    void add_question(const Dictionary &p_question);
    void remove_question(int p_index);
    Array get_questions() const;
    void set_questions(const Array &p_questions);
    
    // Explanation methods
    bool has_explanation(int p_question_index) const;
    Dictionary get_question_explanation(int p_question_index) const;
};