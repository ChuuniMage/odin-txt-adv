package enbench;

import "core:fmt";
import "core:mem"
import "core:strings";
import "core:slice";
import "core:os";
import "core:intrinsics"
import "core:container/small_array";

const_def :: "::"
open_scope :: "{\n"
close_scope :: "\n}\n"
open_bracket :: "["
close_bracket :: "]"

ENUM_NAME :: distinct string

ENUM :: struct {
	name:[dynamic]ENUM_NAME,
	cases:[dynamic][dynamic]string,
}

ENUM_RELATION_TYPE :: enum {
	Enum_Name,
	Description,
}

ENUM_CASE_RELATIONS :: struct {
	enum_name:[dynamic][dynamic]int,
	description:[dynamic][dynamic]string,
}

Backings :: struct {
    case_backing:[dynamic][dynamic][64]u8, // [each_enum]
    description_backing:[dynamic][dynamic][128]u8,
}

backing_from_dtw :: proc (backing:^Backings, dtw:^DataToWrite) {
    for e, idx in &dtw.ENUM.name {
        append(&backing.case_backing, make([dynamic][64]u8))
        append(&backing.description_backing, make([dynamic][128]u8))

        for c in &dtw.ENUM.cases[idx] {
            new_backing := new([64]u8)
            copy(new_backing[:], c)
            append(&backing.case_backing[idx], new_backing^)
            c = cast(string)new_backing[:len(c)]
        }
        for c in &dtw.CASE_RELATIONS.description[idx] {
            error_msg :: "Error! Description over 128 chars in length!\n"
            if len(c) > 127 {
                fmt.printf("Error! Description for %v %v over 128 chars in length!\n")
            }
            new_backing := new([128]u8)
            copy(new_backing[:], c)
            append(&backing.description_backing[idx], new_backing^)
            c = cast(string)new_backing[:len(c)]
        }

    }
}

init_case_relations :: proc (dtw:^DataToWrite) {
	dtw.CASE_RELATIONS.enum_name = make([dynamic][dynamic]int) //enum->case->enum_idx
	for _, idx in dtw.ENUM.name {
		new_int_dynarr := make([dynamic]int)
		for _idx in 0..<len(dtw.ENUM.cases[idx]) do append(&new_int_dynarr, -1)
		append(&dtw.CASE_RELATIONS.enum_name, new_int_dynarr)

		new_desc_dynarr := make([dynamic]string)
		for _idx in 0..<len(dtw.ENUM.cases[idx]) do append(&new_desc_dynarr, "")
		append(&dtw.CASE_RELATIONS.description, new_desc_dynarr)

	}
}

DataToWrite :: struct {
	ENUM:ENUM,
	CASE_RELATIONS:ENUM_CASE_RELATIONS,
}

init_dtw :: proc (dtw:^DataToWrite) {
	dtw.ENUM.name = make([dynamic]ENUM_NAME)
	dtw.ENUM.cases = make([dynamic][dynamic]string)
}

add_enum :: proc (dtw:^DataToWrite, name:string, cases:..string) {
	append(&dtw.ENUM.name, cast(ENUM_NAME)name)
	new_enum_cases := make([dynamic]string)
	for c in cases {
		append(&new_enum_cases, c)
	}
	append(&dtw.ENUM.cases, new_enum_cases)
}

import "core:reflect"


ODINSOURCE_make_enum :: proc (_enum:ENUM, idx:int) -> string{ 
	using strings
	// contents := 
	new_str:= join({cast(string)_enum.name[idx], const_def, "enum", open_scope, concatenate({"\t", join(_enum.cases[idx][:], ",\n\t"), ","})}, " ")
	return concatenate({new_str, close_scope, "\n"})
}

ODINSOURCE_make_e2e_relation :: proc (idx:int, _enum:ENUM, _erel:ENUM_CASE_RELATIONS) -> string {
	using strings
	if slice.all_of(_erel.enum_name[idx][:], -1) do return ""
	e_name := cast(string)_enum.name[idx]
	partial_string := slice.any_of(_erel.enum_name[idx][:], -1) ? "#partial " : ""
	decl := concatenate({e_name, "_enum_relation := ", partial_string, "[", e_name, "] typeid "})
	cases := make([dynamic]string)
	for relation_idx, enum_case in _erel.enum_name[idx] {
		if relation_idx == -1 do continue
		append(&cases, fmt.tprintf("\t.%v = %v,", _enum.cases[idx][enum_case], _enum.name[relation_idx]))
	}
	return concatenate({decl, open_scope, join(cases[:], "\n"), close_scope})
}

ODINSOURCE_make_description :: proc (idx:int, _enum:ENUM, _erel:ENUM_CASE_RELATIONS) -> (string, bool) {
	using strings
	if slice.all_of(_erel.description[idx][:], "") do return "", true
	if slice.any_of(_erel.description[idx][:], "") {
		fmt.printf("Descriptions for %v not handled!", _enum.name[idx])
		return "", false
	}

	e_name := cast(string)_enum.name[idx];
	decl := concatenate({e_name, "_descriptions := ", "[", e_name, "] string "})
	cases := make([dynamic]string)
	fmt.printf("Decl %v \n", decl)
	for description, enum_case in _erel.description[idx] {
		append(&cases, fmt.tprintf("\t.%v = \"%v\",", _enum.cases[idx][enum_case], description))
	}
	return concatenate({decl, open_scope, join(cases[:], "\n"), close_scope}), true
}

CSV_make_enum :: proc (name:string, cases:..string) -> string{
	using strings
	new_str:= join({name, join(cases, ",")}, ",")
	return concatenate({new_str, "\n"})
}

make_writeable :: #force_inline proc (str:string) -> []u8 {
	return transmute([]u8)str
}

make_writeable_flat :: #force_inline proc (str:string) -> ([]u8, bool) {
	return transmute([]u8)str, true
}


remove_more :: proc (str:string, key:..string) -> (output: string, was_allocation: bool) {
	output = str
	was_allocation = false
	for elem in key {
		output, was_allocation = strings.remove_all(output,elem, context.allocator)
	}
	return
}

flatmapper :: proc(a: []$S/[]$U, f: proc(U) -> ($V, bool), allocator := context.allocator) -> []V { // experimental
	if len(a) == 0 {
		return
	}
	n := 0
	for s in a {
		n += len(s)
	}
	r := make([dynamic]V, n, allocator)
	for u in a {
		for e in u {
			elem, ok := f(e)
			if ok do append(&r, elem)
		}
	}
	shrink(r)
	return r[:]
}

delete_enum :: proc (dtw:^DataToWrite, idx:int) {
	delete(dtw.CASE_RELATIONS.enum_name[idx])
	ordered_remove(&dtw.CASE_RELATIONS.enum_name, idx)
	delete(dtw.CASE_RELATIONS.description[idx])
	ordered_remove(&dtw.CASE_RELATIONS.description, idx)
	ordered_remove(&dtw.ENUM.name, idx)
	delete(dtw.ENUM.cases[idx])
	ordered_remove(&dtw.ENUM.cases, idx)
}


read_file_by_lines_in_whole_sweepscan :: proc (filepath:string, dtw:^DataToWrite) {
	data, ok := os.read_entire_file(filepath, context.allocator)
	if !ok {
		fmt.printf("Could not read file. \n")
		return
	}
	defer delete(data, context.allocator)

	enum_scanning_proc :: proc (line:string, dtw:^DataToWrite) {
		fmt.printf("Input: %v \n", line)
		split_line := strings.split(line, " ")
		@static new_ENUM_cases := [32]string{}
		@static cases_idx := 0
		@static enum_found := false
		switch {
			case !enum_found:
				if !slice.contains(split_line, "enum") do return
				append(&dtw.ENUM.name, cast(ENUM_NAME)strings.clone(split_line[0]))
				enum_found = true
			case split_line[0] == "}":
				new_dyn := make([dynamic]string)
				for idx in 0..<cases_idx {
					append(&new_dyn, new_ENUM_cases[idx])
				}
				append(&dtw.ENUM.cases, new_dyn)
				mem.zero_item(&new_ENUM_cases)
				cases_idx = 0
				enum_found = false
			case:
				term, ok := strings.remove_all(line, "\t")
				term, ok = strings.remove_all(term, " ")
				term, ok = strings.remove_all(term, ",")
				new_ENUM_cases[cases_idx] = term
				cases_idx += 1
		}
	}

	relation_scanning_proc :: proc (line:string, dtw:^DataToWrite, enum_names:[]string) {
		split_line := strings.split(line, " ")

		@static base_enum_idx := -1
		@static ENUM_RELATION_TYPE :ENUM_RELATION_TYPE = .Enum_Name

		switch {
			case base_enum_idx == -1:
				for testname in enum_names {
					if !slice.contains(split_line, testname) do continue
					for elem in split_line {
						if strings.contains(elem, "_enum_relation") do ENUM_RELATION_TYPE = .Enum_Name
						if strings.contains(elem, "_descriptions") do ENUM_RELATION_TYPE = .Description
						if !strings.contains(elem, "[") do continue
						base_enum, _ := strings.remove_all(elem, "[")
						base_enum, _ = strings.remove_all(base_enum, "]")
						base_enum_idx, _ = slice.linear_search(dtw.ENUM.name[:], cast(ENUM_NAME)base_enum) 
						return
					}
				}
			case split_line[0] == "}": base_enum_idx = -1; ENUM_RELATION_TYPE = .Enum_Name
			case:
				_case, _ := strings.remove_all(split_line[0], "\t.")
				case_idx, case_ok := slice.linear_search(dtw.ENUM.cases[base_enum_idx][:], _case)
				if !case_ok {
					fmt.printf("Error! Case for %v not found! idx %v \n", _case, case_idx)
				}
				switch ENUM_RELATION_TYPE {
					case .Enum_Name:
						_assigned_enum, _ := strings.remove_all(split_line[2], ",")
						assigned_enum_idx, _ := slice.linear_search(dtw.ENUM.name[:], cast(ENUM_NAME)_assigned_enum)
						fmt.printf("vals, %v %v %v \n", base_enum_idx, case_idx, assigned_enum_idx)
						fmt.printf("On line: %v \n", split_line)
						fmt.printf("Length of case relations for %v %v \n",  base_enum_idx, len(dtw.CASE_RELATIONS.enum_name[base_enum_idx]))
						fmt.printf("Case idx -> %v \n", case_idx)
						dtw.CASE_RELATIONS.enum_name[base_enum_idx][case_idx] = assigned_enum_idx
					case .Description:
						find_quote :: proc(s:rune) -> bool {return s != '\"'}
						the_string := strings.trim_left_proc(line, find_quote)
						the_string = strings.trim_right_proc(the_string, find_quote)
						honk := the_string[1:len(the_string)-1]
						fmt.printf("Assigning %v to %v \n", _case, honk)
						dtw.CASE_RELATIONS.description[base_enum_idx][case_idx] = strings.clone(honk)
				}
		}
	}

	str:= string(data);

    for line in strings.split_lines_iterator(&str) do enum_scanning_proc(line, dtw)
	init_case_relations(dtw)

	str = string(data); 
	enum_names:[]string = slice.mapper(dtw.ENUM.name[:], proc (s:ENUM_NAME) -> string {return fmt.tprintf("[%v]", cast(string)s)})
	for line in strings.split_lines_iterator(&str) do relation_scanning_proc(line, dtw, enum_names)
}


write_data_to_file :: proc(filename:string, pkg_name:string, dtw:^DataToWrite) {
	context.allocator = context.temp_allocator
	str_2_cat := make([dynamic]string)
	append(&str_2_cat, fmt.tprintf("package %v;\n\n", pkg_name))
	append(&str_2_cat, "import \"core:slice\"\n" )

	for _, idx in dtw.ENUM.name {
		_enum := ODINSOURCE_make_enum(dtw.ENUM, idx)
		append(&str_2_cat, _enum)
	}
	for _, idx in dtw.ENUM.name {
		relation := ODINSOURCE_make_e2e_relation(idx, dtw.ENUM, dtw.CASE_RELATIONS)
		append(&str_2_cat, relation)
	}

	for _, idx in dtw.ENUM.name {
		description, ok := ODINSOURCE_make_description(idx, dtw.ENUM, dtw.CASE_RELATIONS)
		if !ok {
			fmt.printf(description); return;
		}
		append(&str_2_cat, description)
		append(&str_2_cat, "\n")
		
	}


	using slice

	data_to_write := concatenate(mapper(str_2_cat[:], make_writeable))
	succ := os.write_entire_file(filename, data_to_write)
}