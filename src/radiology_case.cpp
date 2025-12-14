#include "radiology_case.h"
#include <godot_cpp/core/class_db.hpp>

void RadiologyCase::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_case_name", "name"), &RadiologyCase::set_case_name);
    ClassDB::bind_method(D_METHOD("get_case_name"), &RadiologyCase::get_case_name);
    
    ClassDB::bind_method(D_METHOD("set_case_description", "description"), &RadiologyCase::set_case_description);
    ClassDB::bind_method(D_METHOD("get_case_description"), &RadiologyCase::get_case_description);
    
    ClassDB::bind_method(D_METHOD("set_dicom_file_paths", "paths"), &RadiologyCase::set_dicom_file_paths);
    ClassDB::bind_method(D_METHOD("get_dicom_file_paths"), &RadiologyCase::get_dicom_file_paths);
    
    ClassDB::bind_method(D_METHOD("add_question", "question"), &RadiologyCase::add_question);
    ClassDB::bind_method(D_METHOD("remove_question", "index"), &RadiologyCase::remove_question);
    ClassDB::bind_method(D_METHOD("get_questions"), &RadiologyCase::get_questions);
    ClassDB::bind_method(D_METHOD("set_questions", "questions"), &RadiologyCase::set_questions);
    
    ClassDB::bind_method(D_METHOD("has_explanation", "question_index"), &RadiologyCase::has_explanation);
    ClassDB::bind_method(D_METHOD("get_question_explanation", "question_index"), &RadiologyCase::get_question_explanation);
    
    ClassDB::bind_method(D_METHOD("to_dict"), &RadiologyCase::to_dict);
    ClassDB::bind_method(D_METHOD("from_dict", "dict"), &RadiologyCase::from_dict);

    ADD_PROPERTY(PropertyInfo(Variant::STRING, "case_name"), "set_case_name", "get_case_name");
    ADD_PROPERTY(PropertyInfo(Variant::STRING, "case_description"), "set_case_description", "get_case_description");
    ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "dicom_file_paths"), "set_dicom_file_paths", "get_dicom_file_paths");
    ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "questions"), "set_questions", "get_questions");
}

RadiologyCase::RadiologyCase() {
    case_name = "";
    case_description = "";
}

void RadiologyCase::set_case_name(const String &p_name) {
    case_name = p_name;
}

String RadiologyCase::get_case_name() const {
    return case_name;
}

void RadiologyCase::set_case_description(const String &p_desc) {
    case_description = p_desc;
}

String RadiologyCase::get_case_description() const {
    return case_description;
}

void RadiologyCase::set_dicom_file_paths(const Array &p_paths) {
    dicom_file_paths = p_paths;
}

Array RadiologyCase::get_dicom_file_paths() const {
    return dicom_file_paths;
}

void RadiologyCase::add_question(const Dictionary &p_question) {
    questions.push_back(p_question);
}

void RadiologyCase::remove_question(int p_index) {
    if (p_index >= 0 && p_index < questions.size()) {
        questions.remove_at(p_index);
    }
}

Array RadiologyCase::get_questions() const {
    return questions;
}

void RadiologyCase::set_questions(const Array &p_questions) {
    questions = p_questions;
}

bool RadiologyCase::has_explanation(int p_question_index) const {
    if (p_question_index < 0 || p_question_index >= questions.size()) {
        return false;
    }
    
    Dictionary question = questions[p_question_index];
    if (!question.has("explanation")) {
        return false;
    }
    
    Dictionary explanation = question["explanation"];
    String text = explanation.get("text", "");
    Array images = explanation.get("images", Array());
    
    return !text.is_empty() || images.size() > 0;
}

Dictionary RadiologyCase::get_question_explanation(int p_question_index) const {
    Dictionary empty_explanation;
    empty_explanation["text"] = "";
    empty_explanation["images"] = Array();
    
    if (p_question_index < 0 || p_question_index >= questions.size()) {
        return empty_explanation;
    }
    
    Dictionary question = questions[p_question_index];
    if (!question.has("explanation")) {
        return empty_explanation;
    }
    
    return question["explanation"];
}

Dictionary RadiologyCase::to_dict() const {
    Dictionary dict;
    dict["case_name"] = case_name;
    dict["case_description"] = case_description;
    dict["dicom_file_paths"] = dicom_file_paths;
    dict["questions"] = questions;
    return dict;
}

void RadiologyCase::from_dict(const Dictionary &p_dict) {
    if (p_dict.has("case_name")) {
        case_name = p_dict["case_name"];
    }
    if (p_dict.has("case_description")) {
        case_description = p_dict["case_description"];
    }
    if (p_dict.has("dicom_file_paths")) {
        dicom_file_paths = p_dict["dicom_file_paths"];
    }
    if (p_dict.has("questions")) {
        questions = p_dict["questions"];
    }
}