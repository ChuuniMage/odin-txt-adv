package main;

import "core:fmt"
import "core:os"
import "core:slice"
import "enbench"

import "core:mem";
import "core:log";
import "core:strings";
import "core:runtime";
import "core:reflect"

import sdl "vendor:sdl2";
import gl  "vendor:OpenGL";

import imgui "odin-imgui";
import imgl  "odin-imgui/impl/opengl";
import imsdl "odin-imgui/impl/sdl";

enum_filename :: "../init/sftn-enums.hot.odin"
package_name :: "init"

DESIRED_GL_MAJOR_VERSION :: 4;
DESIRED_GL_MINOR_VERSION :: 5;

get_cstr_end :: proc (b:[]u8) -> int {
    len := 0
    for c in b[:] {
        if c == 0 || c == '\x00' do break
        len += 1
    }
    return len
}

main :: proc() {

    using enbench
    dtw :DataToWrite
    init_dtw(&dtw)
    read_file_by_lines_in_whole_sweepscan(enum_filename, &dtw)
    backings := Backings{
        case_backing = make([dynamic][dynamic][64]u8),
        view_description_backing = make([dynamic][dynamic][128]u8),
    }

    backing_from_dtw(&backings, &dtw)

    default_thingo :: proc () {}

    logger_opts := log.Options {
        .Level,
        .Line,
        .Procedure,
    };
    context.logger = log.create_console_logger(opt = logger_opts);

    log.info("Starting SDL Example...");
    init_err := sdl.Init({.VIDEO});
    defer sdl.Quit();
    if init_err != 0 {
        log.debugf("Error during SDL init: (%d)%s", init_err, sdl.GetError());
        return
    }

    log.info("Setting up the window...");
    window := sdl.CreateWindow("odin-imgui SDL+OpenGL example", 100, 100, 1280, 720, { .OPENGL, .MOUSE_FOCUS, .SHOWN, .RESIZABLE});
    if window == nil {
        log.debugf("Error during window creation: %s", sdl.GetError());
        sdl.Quit();
        return;
    }
    defer sdl.DestroyWindow(window);

    log.info("Setting up the OpenGL...");
    sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, DESIRED_GL_MAJOR_VERSION);
    sdl.GL_SetAttribute(.CONTEXT_MINOR_VERSION, DESIRED_GL_MINOR_VERSION);
    sdl.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(sdl.GLprofile.CORE));
    sdl.GL_SetAttribute(.DOUBLEBUFFER, 1);
    sdl.GL_SetAttribute(.DEPTH_SIZE, 24);
    sdl.GL_SetAttribute(.STENCIL_SIZE, 8);
    gl_ctx := sdl.GL_CreateContext(window);
    if gl_ctx == nil {
        log.debugf("Error during window creation: %s", sdl.GetError()); 
        return;
    }
    sdl.GL_MakeCurrent(window, gl_ctx);
    defer sdl.GL_DeleteContext(gl_ctx);
    if sdl.GL_SetSwapInterval(1) != 0 {
        log.debugf("Error during window creation: %s", sdl.GetError());
        return;
    }
    gl.load_up_to(DESIRED_GL_MAJOR_VERSION, DESIRED_GL_MINOR_VERSION, sdl.gl_set_proc_address);
    gl.ClearColor(0.25, 0.25, 0.25, 1);

    imgui_state := init_imgui_state(window);

    running := true;
    show_demo_window := false;
    e := sdl.Event{};

    for running {
        for sdl.PollEvent(&e) {
            imsdl.process_event(e, &imgui_state.sdl_state);
            #partial switch e.type {
                case .QUIT:
                    log.info("Got SDL_QUIT event!");
                    running = false;
                case .KEYDOWN: #partial switch e.key.keysym.sym {
                    case .ESCAPE: sdl.PushEvent(&sdl.Event{type = .QUIT});
                    case .TAB: if imgui.get_io().want_capture_keyboard == false do show_demo_window = true;
                }
            }
        }

        imgui_new_frame(window, &imgui_state);
        imgui.new_frame();
        
        info_overlay();

        if show_demo_window do imgui.show_demo_window(&show_demo_window);

        idx := input_text_window(&dtw, &backings);
        enum_window(idx, &dtw, &backings)
        enum_relation_window(idx, &dtw, &backings)
        compile_window(&dtw)
        
        imgui.render();

        io := imgui.get_io();
        gl.Viewport(0, 0, i32(io.display_size.x), i32(io.display_size.y));
        gl.Scissor(0, 0, i32(io.display_size.x), i32(io.display_size.y));
        gl.Clear(gl.COLOR_BUFFER_BIT);
        imgl.imgui_render(imgui.get_draw_data(), imgui_state.opengl_state);
        sdl.GL_SwapWindow(window);
    }
    log.info("Shutting down...");

}

info_overlay :: proc() {
    imgui.set_next_window_pos(imgui.Vec2{10, 10});
    imgui.set_next_window_bg_alpha(0.2);
    overlay_flags: imgui.Window_Flags = .NoDecoration | 
                                        .AlwaysAutoResize | 
                                        .NoSavedSettings | 
                                        .NoFocusOnAppearing | 
                                        .NoNav | 
                                        .NoMove;
    imgui.begin("Info", nil, overlay_flags);
    imgui.text_unformatted("Press Esc to close the application");
    imgui.text_unformatted("Press Tab to show demo window");
    imgui.end();
}

enum_relation_window :: proc (idx:int, dtw:^enbench.DataToWrite, backings:^enbench.Backings) { 
    imgui.begin("Enum Relations"); defer imgui.end();
	imgui.text(cast(string)dtw.ENUM.name[idx])
    relations := dtw.CASE_RELATIONS.enum_name[idx]

    case_names := dtw.ENUM.cases[idx]
    enum_names := slice.concatenate([][]string{[]string{"nil"}, transmute([]string)dtw.ENUM.name[:]})

    if !imgui.begin_tab_bar("Tabs") do return
    defer imgui.end_tab_bar()

    if imgui.begin_tab_item("Enum to Enum") {
        defer imgui.end_tab_item()

        for name, c_idx in case_names {
            imgui.text(name)
            imgui.same_line()
            relation_idx := relations[c_idx] + 1
            tested_name := enum_names[relation_idx]
            if !imgui.begin_combo(fmt.tprintf("##rel_combo%v", c_idx), relation_idx == 0 ? "nil" : tested_name) do continue; 
            defer imgui.end_combo();
            for name, combo_idx in enum_names {
                is_selected := combo_idx == relation_idx;
                if imgui.selectable(name, is_selected) do relations[c_idx] = name == "nil" ? -1 : combo_idx -1;//Selectable is generated here?
                if is_selected do imgui.set_item_default_focus();
            }
        }
    }

    if imgui.begin_tab_item("View Description") {
        defer imgui.end_tab_item()
        @static opt_enums_initted := false
        DESCRIPTION_REL_OPTION :: enum {
            Solo,
            Derived,
        }



        @static option_enums : [dynamic]DESCRIPTION_REL_OPTION
        @static derived_option_enums :[dynamic]Maybe(enbench.ENUM_RELATION_TYPE)
        gronk :: proc(a:Maybe(enbench.ENUM_RELATION_TYPE)) -> int {
            switch v in a {
                 case enbench.ENUM_RELATION_TYPE:
                    switch v {
                        case .Enum_Name: return 1
                        case .View_Description: return 2
                        case .Inv_Description: return 3
                    }
            }
            return 0
        }
        if !opt_enums_initted {
            option_enums = make([dynamic]DESCRIPTION_REL_OPTION)
            derived_option_enums = make([dynamic]Maybe(enbench.ENUM_RELATION_TYPE))
            for name in case_names{
                append(&option_enums, DESCRIPTION_REL_OPTION.Solo)
                append(&derived_option_enums, nil)
            }
            opt_enums_initted = true
        }

        for name, c_idx in case_names {
            imgui.text(name)
            imgui.same_line()

            option_switch: switch option_enums[c_idx] {
                case .Solo:
                    imgui.input_text(fmt.tprintf("##view_desc_input%v", c_idx), backings.view_description_backing[idx][c_idx][:])
                    b := backings.view_description_backing[idx][c_idx]
                    dtw.CASE_RELATIONS.view_description[idx][c_idx] = transmute(string)backings.view_description_backing[idx][c_idx][:get_cstr_end(b[:])]
                case .Derived:
                    // imgui.text("Placeholder")
                    enum_names := reflect.enum_field_names(enbench.ENUM_RELATION_TYPE)
                    nilstr := []string{"nil"}
                    combo_names := slice.concatenate([][]string{nilstr, enum_names})

                    if !imgui.begin_combo(fmt.tprintf("##derived_combo%v", c_idx), combo_names[gronk(derived_option_enums[c_idx])]) do break option_switch; 
                    defer imgui.end_combo();
                    for name, combo_idx in combo_names {
                        is_selected := combo_idx == gronk(derived_option_enums[c_idx]);
                        if imgui.selectable(name, is_selected) {
                            _enum, name_ok := reflect.enum_from_name(enbench.ENUM_RELATION_TYPE, name)
                            derived_option_enums[c_idx] = Maybe(enbench.ENUM_RELATION_TYPE)(name_ok ? _enum : nil)
                        } 
                        if is_selected do imgui.set_item_default_focus();
                    }
            }
            imgui.same_line()
            options := reflect.enum_field_names(DESCRIPTION_REL_OPTION)

            if !imgui.begin_combo(fmt.tprintf("##rel_combo%v", c_idx), options[option_enums[c_idx]]) do continue; 
            defer imgui.end_combo();
            for name, combo_idx in options {
                is_selected := combo_idx == cast(int)option_enums[c_idx];
                if imgui.selectable(name, is_selected) do option_enums[c_idx] = cast(DESCRIPTION_REL_OPTION)combo_idx;//Selectable is generated here?
                if is_selected do imgui.set_item_default_focus();
            }
        }
    }

    if imgui.begin_tab_item("Inv Description") {
        defer imgui.end_tab_item()

        for name, c_idx in case_names {
            imgui.text(name)
            imgui.same_line()
            b := backings.inv_description_backing[idx][c_idx]
            imgui.input_text(fmt.tprintf("##inv_desc_input%v", c_idx), backings.inv_description_backing[idx][c_idx][:])
            len := 0
            for c in b[:] {
                if c == 0 || c == '\x00' do break
                len += 1
            }
            dtw.CASE_RELATIONS.inv_description[idx][c_idx] = transmute(string)backings.inv_description_backing[idx][c_idx][:len]
        }
    }
}

enum_window :: proc (idx:int, dtw:^enbench.DataToWrite, backings:^enbench.Backings) {
	imgui.begin("Current Enum"); defer imgui.end();
	imgui.text(cast(string)dtw.ENUM.name[idx])

    backing_buffers := &backings.case_backing[idx]

	for b, _idx in backing_buffers {
		imgui.input_text(fmt.tprintf("##cases%v", _idx), b[:])
        len := 0
        for c in b[:] {
            if c == 0 || c == ' ' do break
            len += 1
        }
        dtw.ENUM.cases[idx][_idx] = cast(string)b[:len]

		imgui.same_line()
        if imgui.button(fmt.tprintf("X##cases$v", _idx)) {
            ordered_remove(backing_buffers, _idx)
            ordered_remove(&dtw.ENUM.cases[idx], _idx)
        }
	}

    @static newtext_buff : [64]u8
	imgui.input_text("\n", newtext_buff[:])

    imgui.same_line()
    if imgui.button("Add case") {
        len := 0
        for c in newtext_buff[:] {
            if c == 0 || c == ' ' do break
            len += 1
        }
        if len > 0 {
            new_backing := new([64]u8)
            copy(new_backing[:], newtext_buff[:len])
            append(&backings.case_backing[idx], new_backing^)
            append(&dtw.ENUM.cases[idx], cast(string)new_backing[:len])
            append(&dtw.CASE_RELATIONS.enum_name[idx], -1)
            mem.zero_slice(newtext_buff[:])
        }
    }
}

input_text_window :: proc(dtw:^enbench.DataToWrite, backings:^enbench.Backings) -> int {
    imgui.begin("Main Enums"); defer imgui.end();
	@static new_enum_buff := [64]u8{}
	imgui.input_text("##new_enum", new_enum_buff[:])
	imgui.same_line()

	if imgui.button("Add Enum") {
        len := 0
        for c in new_enum_buff[:] {
            if c == 0 || c == ' ' do break
            len += 1
        }
        if len > 0 {
            new_backing := new([64]u8)
            using enbench
            add_enum(dtw, strings.clone_from_bytes(new_enum_buff[:len]))
            append(&backings.case_backing, make([dynamic][64]u8))
            // append(&backings.enum_relation_backing, make([dynamic][64]u8))
            // append(&_enum.cases, cast(string)new_backing[:len])
            mem.zero_slice(new_enum_buff[:])
        }
    }

    @static item_current_index := 0
    if imgui.begin_list_box("##enums") { defer imgui.end_list_box()
        for e, _idx in dtw.ENUM.name {
            is_selected := item_current_index == _idx
            if imgui.selectable(cast(string)e, is_selected) do item_current_index = _idx
        }
    }
    imgui.same_line()
    if imgui.button("Delete Enum") {
        if item_current_index == len(dtw.ENUM.name) - 1 do defer item_current_index -= 1

        old_names := slice.mapper(dtw.ENUM.name[:], proc(s:enbench.ENUM_NAME) -> string {return cast(string)s}, context.temp_allocator)

        enbench.delete_enum(dtw, item_current_index)

        for x in &backings.case_backing[item_current_index] do free(&x)
        ordered_remove(&backings.case_backing, item_current_index)

        new_names := slice.mapper(dtw.ENUM.name[:], proc(s:enbench.ENUM_NAME) -> string {return cast(string)s}, context.temp_allocator)
        new_indices := make([]int, len(old_names), context.temp_allocator)
        
        for name, idx in old_names {
            f_idx, found := slice.linear_search(new_names, name)
            new_indices[idx] = found ? f_idx : -1
        }

        for rel in &dtw.CASE_RELATIONS.enum_name {
            for num in &rel do num = num == -1 ? num : new_indices[num]
        }
    }
 
	return item_current_index
}

compile_window :: proc(dtw:^enbench.DataToWrite) {
    imgui.begin("Compile button"); defer imgui.end()
    if imgui.button("Compile!") {
        enbench.write_data_to_file(enum_filename, package_name, dtw)
    }
}

Imgui_State :: struct {
    sdl_state: imsdl.SDL_State,
    opengl_state: imgl.OpenGL_State,
}

init_imgui_state :: proc(window: ^sdl.Window) -> Imgui_State {
    using res := Imgui_State{};

    imgui.create_context();
    imgui.style_colors_dark();

    imsdl.setup_state(&res.sdl_state);
    
    imgl.setup_state(&res.opengl_state);

    return res;
}

imgui_new_frame :: proc(window: ^sdl.Window, state: ^Imgui_State) {
    imsdl.update_display_size(window);
    imsdl.update_mouse(&state.sdl_state, window);
    imsdl.update_dt(&state.sdl_state);
}
