package main

import "vendor:sdl2";
import "core:fmt"

ImmUI_Elem :: enum {
    HorizontalSelect,
    Text,
    Button,
    BlankLine,
    SameLine,
}

ImmUI_Indexed :: struct {
    text:string,
    idx:u8,
}

ImmUI_Selection :: struct {
    text:string,
    selections:[]string,
    idx:u8,
}

ImmUI_Data :: union {
    string,
    ImmUI_Indexed,
    ImmUI_Selection,
    ImmUI_BlankMode,
}


Cursor :: struct {
    selection, max: i8,
}

SFTN_ImmUI :: struct {
    static_cursor:^Cursor,
    running_cursor:i8,
    origin:[2]i32,
    elem_stack:[dynamic]ImmUI_Elem,
    elem_data:[dynamic]ImmUI_Data,
}

SFTN_RightClick :: struct {
    origin:[2]i32,
    elem_data:[dynamic]string,
    running_elem_idx:i32,
    static_max_str_len:int,
    hovered_idx:i32,
}

rc_menu_start :: proc (rc_menu:^SFTN_RightClick, origin:[2]i32) {
    rc_menu.origin = origin;
    rc_menu.hovered_idx = -1;
}

rc_menu_button :: proc (rc_menu:^SFTN_RightClick, str:string, mouse_event:^sdl2.Event) -> bool {
    rc_menu_push(rc_menu, str)

    _len := cast(i32)len(str)
    ul_offset := [2]i32{0,(16*rc_menu.running_elem_idx)}
    br_offset := [2]i32{_len * 9,16+(16*rc_menu.running_elem_idx)}
    option_pt_ul := rc_menu.origin + ul_offset
    option_pt_br := rc_menu.origin + br_offset

    if rc_menu.hovered_idx == -1 && point_within_bounds(MOUSE_PT, option_pt_ul, option_pt_br) {
        rc_menu.hovered_idx = rc_menu.running_elem_idx
        rc_menu.running_elem_idx += 1
        return true
    }
    rc_menu.running_elem_idx += 1
    return false
}

rc_menu_push :: #force_inline proc(menu:^SFTN_RightClick, str:string) {
    append(&menu.elem_data, str)
}

rc_menu_end :: proc (using ge:^GlobalEverything, using menu:^SFTN_RightClick, mouse_event:^sdl2.Event) -> bool {
    max_string_length := 0
    v_elems := 0
    for x in menu.elem_data {
        max_string_length = max(len(x), max_string_length)
        v_elems += 1
    }

    filler_dims := [2]i32{
        cast(i32)max_string_length ,
        cast(i32)(v_elems),
    }

    running_origin := origin
    default_offset :=  [2]i32{cast(i32)ui.font_rect.w, cast(i32)ui.font_rect.h}

    current_palette := ge.palettes[ge.view_palettes[ge.current_view_enum]]
    swap_palette : [4]u32 = swizzle(current_palette, 3, 1, 2, 0)

    for s in &ge.font_surface_array {
        replace_palette(s, &current_palette, &swap_palette);
    };
    defer for s in &ge.font_surface_array {
        replace_palette(s, &swap_palette, &current_palette);
    };

    for str, i in menu.elem_data {

        if i == cast(int)menu.hovered_idx { // NOTE: With an actual palette system, could do a more efficient blit
            for s in &ge.font_surface_array {
                replace_palette(s, &swap_palette, &current_palette);
            };
        }
        defer if i == cast(int)menu.hovered_idx {
            for s in &ge.font_surface_array {
                replace_palette(s, &current_palette, &swap_palette);
            };
        }
        for x in 0..<filler_dims.x {
            blit_tile(ge, ui.font_surface_array[char_to_index(' ')], running_origin + {ui.font_rect.w*cast(i32)x, 0})
        }
        blit_text(ge, str, running_origin)
        running_origin += {0, cast(i32)ui.font_rect.h}

    }

    delete(menu.elem_data)
    return mouse_event.button.button == .LEFT 
}

menu_start :: proc (menu:^SFTN_ImmUI, origin:[2]i32) {
    menu.static_cursor.max = -1
    menu.origin = origin
}

menu_push :: #force_inline proc(menu:^SFTN_ImmUI, t:ImmUI_Elem, d:ImmUI_Data) {
    append(&menu.elem_stack, t)
    append(&menu.elem_data, d)
}

menu_same_line :: proc (using menu:^SFTN_ImmUI)  {
    menu_push(menu, .SameLine, nil)
}

menu_noui_blank_continue :: proc (menu:^SFTN_ImmUI, event:^sdl2.Event) -> bool {
    return  event.type == .KEYDOWN && event.key.keysym.sym == .RETURN 
}

menu_button :: proc (menu:^SFTN_ImmUI, str:string, event:^sdl2.Event) -> bool {
    menu_push(menu, .Button, str)
    cursor_selected := menu.static_cursor.selection == menu.running_cursor
    menu.running_cursor += 1
    return cursor_selected && event.type == .KEYDOWN && event.key.keysym.sym == .RETURN 
}

menu_horizontal_select :: proc (menu:^SFTN_ImmUI, str:string, event:^sdl2.Event, selections:[]string, selection_idx:^u8) -> bool {
    deref_idx := selection_idx^
    cursor_selected := menu.static_cursor.selection == menu.running_cursor
    if cursor_selected { #partial switch event.type {
            case .KEYDOWN: #partial switch event.key.keysym.sym {
                case .LEFT: selection_idx^ = deref_idx == 0 ? 0 : deref_idx - 1
                case .RIGHT: selection_idx^ = deref_idx == cast(u8)len(selections) -1 ? cast(u8)len(selections) -1 : deref_idx + 1
            }
        }
    }

    selections_data := ImmUI_Selection{
        text = str,
        selections = selections[:],
        idx = deref_idx,
    }

    menu_push(menu, .HorizontalSelect, selections_data)
    menu.running_cursor += 1
    return cursor_selected && event.type == .KEYDOWN && event.key.keysym.sym == .RETURN 
}

ImmUI_BlankMode :: enum {
    Full,
    Half,
}

menu_blank :: proc (menu:^SFTN_ImmUI, mode : ImmUI_BlankMode = .Full) {menu_push(menu, .BlankLine, mode)}

menu_text :: proc (menu:^SFTN_ImmUI, str:string) {menu_push(menu, .Text, str)}

menu_end :: proc (using ge:^GlobalEverything, using menu:^SFTN_ImmUI, mode := ImmUI_BlankMode.Full) {
    max_string_length := 0
    v_elems := 0
    for x in menu.elem_data {
        switch v in x {
            case string:
                max_string_length = max(len(v), max_string_length)
            case ImmUI_Indexed:
                max_string_length = max(len(v.text), max_string_length)
            case ImmUI_Selection:
                max_selection_len := 0
                for elem in v.selections {
                    max_selection_len = max(len(elem), max_selection_len)
                }
                max_string_length = max(len(v.text) + max_string_length + 2, max_selection_len)
            case ImmUI_BlankMode:
        }
    }

    for x, i in menu.elem_stack {
        #partial switch x {
            case .BlankLine, .Button, .HorizontalSelect, .Text: v_elems += 1
        }
    }
    filler_dims := [2]i32{
        5 + cast(i32)max_string_length ,
        1 + cast(i32)(v_elems * 2),
    }
    running_origin := origin
    nextline_origin := [2]i32{0,0}
    cursor_option : i8 = 0
    default_offset :=  [2]i32{cast(i32)ui.font_rect.w*3, cast(i32)ui.font_rect.h}

    initial_full_blit_skipped := mode == .Full
    for x, i in menu.elem_stack {
        @static sameline_nextline := [2]i32{0,0}
 
        blit_filler: switch x {
            case .HorizontalSelect:
                for x in 0..<filler_dims.x {
                    blit_tile(ge, ui.font_surface_array[char_to_index(' ')], running_origin + {ui.font_rect.w*cast(i32)x+(cast(i32)len(menu.elem_data[i].(ImmUI_Selection).text)+2), ui.font_rect.h})
                    if !initial_full_blit_skipped do continue
                    blit_tile(ge, ui.font_surface_array[char_to_index(' ')], running_origin + {ui.font_rect.w*cast(i32)x+(cast(i32)len(menu.elem_data[i].(ImmUI_Selection).text)+2), 0})
                }
                fallthrough;
            case .Text, .Button:
                for x in 0..<filler_dims.x {
                    blit_tile(ge, ui.font_surface_array[char_to_index(' ')], running_origin + {ui.font_rect.w*cast(i32)x, ui.font_rect.h})
                    if !initial_full_blit_skipped do continue
                    blit_tile(ge, ui.font_surface_array[char_to_index(' ')], running_origin + {ui.font_rect.w*cast(i32)x, 0})
                }
                initial_full_blit_skipped = true
            case .BlankLine:
                if menu.elem_data[i].(ImmUI_BlankMode) == .Half {
                    for x in 0..<filler_dims.x {
                        blit_tile(ge, ui.font_surface_array[char_to_index(' ')], running_origin + {ui.font_rect.w*cast(i32)x, 0})
                    }
                } else {
                    for x in 0..<filler_dims.x {
                        blit_tile(ge, ui.font_surface_array[char_to_index(' ')], running_origin + {ui.font_rect.w*cast(i32)x, 0})
                        blit_tile(ge, ui.font_surface_array[char_to_index(' ')], running_origin + {ui.font_rect.w*cast(i32)x, ui.font_rect.h})
                    }
                }
            case .SameLine:
        }

        blit_content: switch x {
            case .SameLine:
                sameline_nextline = running_origin
                running_origin -= {0, cast(i32)ui.font_rect.h*2}
                horizontal_offset :i32 = 0 
                switch menu.elem_stack[i-1] {
                    case .SameLine, .BlankLine:
                    case .Text, .Button: 
                        horizontal_offset = cast(i32)len(menu.elem_data[i-1].(string))*ui.font_rect.w
                    case .HorizontalSelect: 
                        data := menu.elem_data[i-1].(ImmUI_Selection)
                        horizontal_offset = cast(i32)(len(data.text)+2 + len(data.selections[data.idx])) * ui.font_rect.w
                }
                running_origin += {horizontal_offset + (ui.font_rect.w*4), 0}
                default_offset = [2]i32{cast(i32)ui.font_rect.w*1, cast(i32)ui.font_rect.h}
                continue
            case .Text:
                blit_text(ge, menu.elem_data[i].(string), running_origin + default_offset)
            case .BlankLine:
            case .Button:
                blit_text(ge, menu.elem_data[i].(string), running_origin + default_offset)
            case .HorizontalSelect:
                data := menu.elem_data[i].(ImmUI_Selection)
                blit_text(ge, data.text, running_origin + default_offset)
                blit_text(ge, data.selections[data.idx], running_origin + default_offset + {ui.font_rect.w*(cast(i32)len(data.text)+2), 0})
        }
        cursor_and_origin: switch x {
            case .Button, .HorizontalSelect:
                menu.static_cursor.max += 1
                if cursor_option == menu.static_cursor.selection {
                    blit_tile(ge, ui.font_surface_array[char_to_index('+')], running_origin + default_offset - {ui.font_rect.w*2, 0})   
                }
                cursor_option += 1
                running_origin += {0, cast(i32)ui.font_rect.h*2}
            case .Text:
                running_origin += {0, cast(i32)ui.font_rect.h*2}
            case .BlankLine:
                if menu.elem_data[i].(ImmUI_BlankMode) == .Half {
                    running_origin += {0, cast(i32)ui.font_rect.h*1}
                } else {
                    running_origin += {0, cast(i32)ui.font_rect.h*2}
                }
            case .SameLine:
        } 

        if sameline_nextline != {0,0} {
            running_origin = sameline_nextline
            sameline_nextline = {0,0}
            default_offset = [2]i32{cast(i32)ui.font_rect.w*3, cast(i32)ui.font_rect.h}
        }
    }
    delete(menu.elem_stack)
    delete(menu.elem_data)
}