package main

import "core:reflect"
import "core:thread"
import "core:fmt";
import "core:strings";
import "core:slice";
import "core:os";
import "core:intrinsics"
import "core:time"
import "core:mem"
import "vendor:sdl2";
import mix "vendor:sdl2/mixer"

NATIVE_WIDTH :: 320
NATIVE_HEIGHT :: 200
TRANSPARENT_COLOURS :: [2]u32{cast(u32)0x00000000, cast(u32)0x00FFFFFF}

MOUSE_PT := [2]i32{}

LENGTH_OF_CHAR_BUFFER_ARRAY :: 36

FPS :: 60;
frameDuration :: 1000 / FPS;

ALLOW_CUTSCENES :: false
PROFILING :: true
MULTITHREADING :: false

when MULTITHREADING {
    elements_per_buffer :: (NATIVE_HEIGHT * NATIVE_WIDTH) / 4
    multithreading_screen_buffers: [4][size_of([2]i32) * elements_per_buffer]byte
    multithreading_arenas : [4]mem.Arena
    multithreading_allocators : [4]mem.Allocator
    global_arena: mem.Arena
    init_thread_arenas :: #force_inline proc () {
        for x, idx in &multithreading_allocators {
            mem.arena_init(&multithreading_arenas[idx], multithreading_screen_buffers[idx][:])
            x = mem.arena_allocator(&global_arena)
        }
    }

}

when PROFILING {
    profiling_ms := make([dynamic]f64)

    profile_start :: proc () -> time.Tick {
        OLD_TIME := time.tick_now()
        return OLD_TIME
    }
    profile_end :: proc (OLD_TIME:time.Tick) -> (time_in_milliseconds:f64) {
        new := time.tick_now()
        diff := time.tick_diff(OLD_TIME, new)
        time_in_milliseconds = time.duration_milliseconds(diff)
        fmt.printf("--- Diff: %v \n", time_in_milliseconds)
        return
    }
} 

Name ::                 distinct string
StateInt ::             distinct int
DialogueStateInt ::     distinct int
CoroInt ::              distinct int
TalkGraphicsStateInt :: distinct int
Location ::             distinct Maybe(VIEW_ENUM)
Descriptions ::         distinct []string
Surfaces ::             distinct []^sdl2.Surface 
TalkSurfaces ::         distinct []^sdl2.Surface 
Synonyms ::             distinct []string

point_to_idx :: proc (s:^sdl2.Surface, pt:[2]i32) -> i32 {return pt.x + (s.w*pt.y)}

blacken_surf :: proc (surf:^sdl2.Surface) {
    mptr := cast([^]u32)surf.pixels
    for x in 0..<surf.w do for y in 0..<surf.h {
        idx := point_to_idx(surf, {x,y})
        mptr[idx] = sdl2.MapRGB(surf.format,0,0,0)
    }
}

render_dialogue_mode :: proc (using ge:^GlobalEverything, event:^sdl2.Event) {
    @static logged_framecount := cast(u64)0
    if logged_framecount+1 < ge.frame_counter {
        event^ = {}
    } 
    logged_framecount = ge.frame_counter

    @static cursor := Cursor{}

    #partial switch event.type { case .KEYDOWN: #partial switch event.key.keysym.sym {
            case .UP: cursor.selection = cursor.selection == 0 ? cursor.selection : cursor.selection - 1
            case .DOWN: cursor.selection = cursor.max == cursor.selection ? cursor.max : cursor.selection + 1
        }
    }

    surfs, talk_state, _ := ecs.get_components(ge.ctx, npc.entities[ge.npc.dialoguing_npc.(NPC_ENUM)], TalkSurfaces, TalkGraphicsStateInt)

    sdl2.BlitSurface(surfs[talk_state^], nil, ge.working_surface, &surfs[talk_state^].clip_rect);
    blit_multiline_string(ge, ge.npc.current_node.dialogue_text)

    menu := SFTN_ImmUI{static_cursor = &cursor}
    menu_start(&menu, {font_rect.w * 17, (NATIVE_HEIGHT) - (font_rect.h * 8 )})
    switch len(ge.npc.current_node.child_nodes) {
        case 1: if menu_noui_blank_continue(&menu, event) {
                if ge.npc.current_node.event_if_chosen != nil do ge.npc.current_node.event_if_chosen(ge)
                cursor.selection = 0
                ge.npc.current_node = ge.npc.current_node.child_nodes[0]
            }
        case 0: if menu_noui_blank_continue(&menu, event) {
                if ge.npc.current_node.event_if_chosen != nil do ge.npc.current_node.event_if_chosen(ge)
                cursor.selection = 0
                ge.game_mode = .Default
            }
        case: for n in &ge.npc.current_node.child_nodes {
                if menu_button(&menu, n.selection_option, event) {
                    if ge.npc.current_node.event_if_chosen != nil do ge.npc.current_node.event_if_chosen(ge)
                    cursor.selection = 0
                    ge.npc.current_node = n
                }
            }
    }
    menu_end(ge, &menu, .Half)
}

GameMode :: enum {
    Default,
    RightClickMenu,
    MainMenu,
    Menu,
    Inventory,
    Dialogue,
    Cutscene,
};

GameProgress :: enum {
    Fresh,
    Zone1,
}

ValidCommand :: enum  {
    Quit,
    Menu,
    Invalid,
    Save,
    Go,
    Look,
    LookInside,
    Take,
    Place,
    Inventory,
    Talk,
    ListExits,
    Exit,
};

ExitDirection :: enum {
    Up,
    Down,
    Left,
    Right,
}

ClickCommand :: enum {
    Go,
    Look,
    LookInside,
    Take,
    Place,
    Talk,
}

VIEW_ENUM :: enum {
	CHURCH,
	CLEARING,
	SKETE,
	CHAPEL,
	SHRINE,
}

ViewType :: enum {
    Room, LookInside,
}

render_inventory_mode :: proc (ge:^GlobalEverything, event:^sdl2.Event) {
    @static logged_framecount := cast(u64)0
    if logged_framecount+1 < ge.frame_counter {
        event^ = {}
    } 
    logged_framecount = ge.frame_counter

    @static cursor := Cursor{}

    #partial switch event.type { case .KEYDOWN: #partial switch event.key.keysym.sym {
        case .UP:       cursor.selection = cursor.selection == 0 ? cursor.selection : cursor.selection - 1
        case .DOWN:     cursor.selection = cursor.max == cursor.selection ? cursor.max : cursor.selection + 1
        case .LEFT:     cursor.selection = cursor.selection % 2 == 1 ? cursor.selection : cursor.selection - 1
        case .RIGHT:    cursor.selection = cursor.selection % 2 == 0 || cursor.selection == cursor.max ? cursor.selection : cursor.selection + 1
        }
    }

    menu := SFTN_ImmUI{static_cursor = &cursor}
    menu_start(&menu, {0,0})
    for x in 0..<cap(ge.pid.inv) {
        if x >= len(ge.pid.inv) {
            menu_text(&menu, "      ")
        } else {
            if menu_button(&menu, un_underscore(reflect.enum_string(ge.pid.inv[x])), event) {
                handle := ge.pid.pi_entities[ge.pid.inv[x]]
                desc, state, _ := ecs.get_components(ge.ctx, handle, Descriptions, StateInt)
                anim_push(&ge.anim, blit_multiline_string, 240, desc[state^])
            }
        }
        if x%2 == 0 do menu_same_line(&menu)
    }
    if menu_button(&menu, "QUIT", event) {
        ge.game_mode = .Default
    }
    menu_same_line(&menu); menu_text(&menu, "      "); 
    menu_blank(&menu, .Half)
    menu_end(ge, &menu)
} 

render_right_click_menu_mode ::proc (using ge:^GlobalEverything, mouse_event:^sdl2.Event){
    menu := SFTN_RightClick{}
    rc_menu_start(&menu, ge.right_clicked_origin)
    clicked := false
    clicked = rc_menu_button(&menu, cast(string)ecs.get_comp(ge.ctx, ge.right_clicked_entity.(ecs.Entity), Name)^, mouse_event) || clicked
    clicked = rc_menu_button(&menu, "LOOK", mouse_event) || clicked
    clicked = rc_menu_button(&menu, "TAKE", mouse_event) || clicked
    honk := bit_set[ValidCommand]{.Exit, .Go}
    for x in ValidCommand{
        if x in honk {

        }
    }
    if rc_menu_end(ge, &menu, mouse_event) {
        if !clicked do ge.game_mode = .Default;
    }

}

render_main_menu_mode :: proc (using ge:^GlobalEverything, event:^sdl2.Event){
    @static logged_framecount := cast(u64)0
    if logged_framecount+1 < ge.frame_counter {
        event^ = {}
    } 
    logged_framecount = ge.frame_counter

    @static cursor := Cursor{}
    #partial switch event.type { case .KEYDOWN: #partial switch event.key.keysym.sym {
        case .UP: cursor.selection = cursor.selection == 0 ? cursor.selection : cursor.selection - 1
        case .DOWN: cursor.selection = cursor.max == cursor.selection ? cursor.max : cursor.selection + 1
        }
    }

    menu := SFTN_ImmUI{static_cursor = &cursor}
    menu_start(&menu, {14*7,48})
    if menu_button(&menu, "NEW GAME", event) {   
        when ALLOW_CUTSCENES == false {
            ge.game_mode = .Default
            ge.game_progress = .Zone1
        } else {
            ge.game_mode = .Cutscene
            ge.csd.coro_int = 0
            ge.csd.current_cutscene = intro_cutscene
            blacken_surf(ge.working_surface)
    
            sdl2.BlitScaled(ge.working_surface, nil, ge.render_surface, nil);
        }
        cursor.selection = 0
        return
    }
    if menu_button(&menu, "LOAD GAME", event) {
        savedata_marshall(&ge.save_data, .READ_FROM_FILE)
        savedata_to_ge(ge, &ge.save_data)
        replace_all_palettes(ge, ge.current_view_enum);
        anim_push(&ge.anim, blit_multiline_string, 240, "Perhaps....?")
    }
    if menu_button(&menu, "EXIT GAME", event) {
        ge.quit = true
        cursor.selection = 0
    }
    menu_blank(&menu, .Half)
    menu_end(ge, &menu)
}

render_menu_mode :: proc (using ge:^GlobalEverything, event:^sdl2.Event){
    @static logged_framecount := cast(u64)0
    if logged_framecount+1 < ge.frame_counter {
        event^ = {}
    } 
    logged_framecount = ge.frame_counter

    @static cursor := Cursor{}

    #partial switch event.type { case .KEYDOWN: #partial switch event.key.keysym.sym {
        case .UP: 
            mix.PlayChannel(-1, ge.audio.menu[.menu_cursor_change], 0)
            cursor.selection = cursor.selection == 0 ? cursor.selection : cursor.selection - 1
        case .DOWN: 
            mix.PlayChannel(-1, ge.audio.menu[.menu_cursor_change], 0)
            cursor.selection = cursor.max == cursor.selection ? cursor.max : cursor.selection + 1
        }
    }

    menu := SFTN_ImmUI{static_cursor = &cursor}
    menu_start(&menu, {0,0})
    @static window_selection := u8(0)
    selection_options := []string{"1", "2", "3", "4", "5"}
    if menu_horizontal_select(&menu, "WINDOW SCALE x", event, selection_options[:], &window_selection) {
        ge.window_size = int(window_selection) + 1
        sdl2.SetWindowSize(window, i32(NATIVE_WIDTH * ge.window_size), i32(NATIVE_HEIGHT * ge.window_size));
        ge.render_surface = sdl2.GetWindowSurface(ge.window);
    }
    if menu_button(&menu, "SAVE", event) {
        handle_command(ge, []Token{{.Command, .Save}}); 
        mix.PlayChannel(-1, ge.audio.menu[.menu_quit], 0)
        ge.game_mode = .Default
        cursor.selection = 0
        return;
    }
    menu_same_line(&menu); menu_text(&menu, "Honk")
    menu_blank(&menu)
    menu_blank(&menu)
    if menu_button(&menu, "QUIT", event) {
        mix.PlayChannel(-1, ge.audio.menu[.menu_quit], 0)
        ge.game_mode = .Default
        cursor.selection = 0
    }
    menu_blank(&menu, .Half)
    menu_end(ge, &menu)
};

AnimData_MouseTextBlit :: struct {
    mouse_pt:[2]i32,
    text:string,
}

AnimData :: union {
    string,
    AnimData_BlitSprite,
    AnimData_BlitSpriteCycle,
    AnimData_MouseTextBlit,
}

anim_push :: proc (anims:^Animations, anim: proc (^GlobalEverything, AnimData), duration:int, data:AnimData) {
    append(&anims.anim_proc, anim)    
    append(&anims.duration, duration)   
    append(&anims.data_to_blit, data)    
}

anim_pop :: proc (anims:^Animations, idx:int) {
    ordered_remove(&anims.anim_proc, idx)  
    ordered_remove(&anims.duration, idx)      
    ordered_remove(&anims.data_to_blit, idx)    
}

anims_advance_one :: #force_inline proc (ge:^GlobalEverything, anims:^Animations ) {
   for anim, idx in anims.anim_proc { using anims;
        if duration[idx] == 0 {anim_pop(anims, idx);continue}
        duration[idx] -= 1
        switch v in &anims.data_to_blit[idx] {
            case string:
            case AnimData_BlitSprite:
            case AnimData_MouseTextBlit:
            case AnimData_BlitSpriteCycle: using v
            v.frame_counter = v.frame_counter + 1
            if frame_counter > duration_per_frame {
                frame_idx = (frame_idx == len(surfs) -1) ? 0 : frame_idx + 1
                frame_counter = 0
            }
        } 
        anim(ge, data_to_blit[idx])
    }
}

Animations :: struct { 
    anim_proc:      [dynamic]proc (^GlobalEverything, AnimData),
    duration:       [dynamic]int,
    data_to_blit:   [dynamic]AnimData,
}

anim_struct_init :: proc (using s:^Animations) {
    anim_proc       = make([dynamic]proc (^GlobalEverything, AnimData))
    duration        = make([dynamic]int)
    data_to_blit    = make([dynamic]AnimData)
}

AnimData_BlitSprite :: struct {
    surf:^sdl2.Surface,
    blit_point:[2]i32,
}

AnimData_BlitSpriteCycle :: struct {
    surfs:[]^sdl2.Surface,
    blit_point:[2]i32,
    duration_per_frame:int,
    frame_counter:int,
    frame_idx:int,
}

blit_sprite :: proc (ge:^GlobalEverything, data:AnimData) {
    _data := data.(AnimData_BlitSprite)
    space_rect:= sdl2.Rect{
        h = _data.surf.clip_rect.h, 
        w = _data.surf.clip_rect.w,
        x = _data.blit_point.x,
        y = _data.blit_point.y,
    }
    sdl2.BlitSurface(_data.surf, nil, ge.working_surface, &space_rect);
}

blit_cycle_animation :: proc (ge:^GlobalEverything, data:AnimData) {
    using _data := data.(AnimData_BlitSpriteCycle)
    blit_sprite(ge, AnimData_BlitSprite{surf = surfs[frame_idx], blit_point = _data.blit_point})
}

intro_cutscene :: proc (ge:^GlobalEverything, coro_state:CoroInt) -> CoroInt {
    @static anims:Animations

    @static bed_sprite:^sdl2.Surface 
    @static novice_sprite:^sdl2.Surface 
    @static flame_sprites:[3]^sdl2.Surface 
    @static candle_sprite:^sdl2.Surface

    switch coro_state {
        case 0:
            anim_struct_init(&anims)
            bed_sprite = sdl2.LoadBMP(fmt.ctprintf("assets/cutscenes/intro/elder-on-bed-1.bmp"))
            novice_sprite = sdl2.LoadBMP(fmt.ctprintf("assets/cutscenes/intro/novice-next-to-bed-1.bmp"))
            candle_sprite = sdl2.LoadBMP(fmt.ctprintf("assets/cutscenes/intro/candle-base.bmp"))
            for x, i in &flame_sprites {
                x = sdl2.LoadBMP(fmt.ctprintf("assets/cutscenes/intro/candle-fire-%v.bmp", i+1))
            }

            anim_push(&anims, blit_sprite, 240, AnimData_BlitSprite{surf = bed_sprite, blit_point = {40, NATIVE_HEIGHT - bed_sprite.h}})
            anim_push(&anims, blit_sprite, 240, AnimData_BlitSprite{surf = novice_sprite, blit_point = {230, NATIVE_HEIGHT - novice_sprite.h}})
            candle_point :i32= 190
            anim_push(&anims, blit_sprite, 240, AnimData_BlitSprite{surf = candle_sprite, blit_point = {candle_point, NATIVE_HEIGHT - candle_sprite.h}})
            anim_push(&anims, blit_cycle_animation, 240, 
                AnimData_BlitSpriteCycle{
                    surfs = flame_sprites[:], 
                    blit_point = {candle_point + 7, NATIVE_HEIGHT - candle_sprite.clip_rect.h - 15},
                    duration_per_frame = 12})
            return 1
        case 1:
            anims_advance_one(ge, &anims)
            if len(anims.anim_proc) != 0 do return 1
            ge.game_mode = .Default
            ge.game_progress = .Zone1
            sdl2.FreeSurface(bed_sprite)
            sdl2.FreeSurface(novice_sprite)
            sdl2.FreeSurface(candle_sprite)
            for surf in &flame_sprites {
                sdl2.FreeSurface(surf)
            }
            return -1
    }
    return -1
}

render_default :: proc (using ge:^GlobalEverything) {
    blit_input_text :: proc (using ge:^GlobalEverything) {
        using text_buffer
        for i in 0..<cap(builder.buf)+4{
            blit_point := [2]i32{cast(i32)i*ge.ui.font_rect.w, NATIVE_HEIGHT - ge.ui.font_rect.h}
            blit_tile(ge, ui.font_surface_array[char_to_index(' ')], blit_point)
        };
        blit_text(ge, string(builder.buf[:]), {0, NATIVE_HEIGHT - ge.ui.font_rect.h});
    }

    blit_quill_anim :: proc (using ge:^GlobalEverything, elems_in_charBuffer:int){
        @static logged_framecount := u64(0); 
        @static animation_frame := 0;

        switch {
            case ge.frame_counter - logged_framecount > 30: 
                animation_frame = 0
                logged_framecount = ge.frame_counter
            case ge.frame_counter - logged_framecount == 30: 
                animation_frame = animation_frame == 3 ? 0 : animation_frame + 1
                logged_framecount = ge.frame_counter
        }
        blit_point := [2]i32{(quill_array[0].clip_rect.w+1) * cast(i32)elems_in_charBuffer, NATIVE_HEIGHT - quill_array[0].clip_rect.h, }
        blit_tile(ge, quill_array[animation_frame], blit_point);
    };

    if len(text_buffer.builder.buf) == 0 do return
    blit_input_text(ge)
    if len(text_buffer.builder.buf) == 35 do return
    blit_quill_anim(ge, len(text_buffer.builder.buf))
}

TokenType :: enum {
    Command,
    Modifier,
    Identifier,
}

ModifierType :: enum {
    Preposition_In,
    Article,
    Preposition_At,
}

TokenData :: union {
    string,
    ValidCommand,
    ModifierType,
}

Token :: struct {
    _type: TokenType,
    data:TokenData,
}

parse_tokens :: proc (ge:^GlobalEverything, strs:[]string) -> []Token {
    tokens := make([dynamic]Token, context.temp_allocator)
    for str in strs {
        tok := Token{}
        switch str {
            case "QUIT":                      tok._type = .Command; tok.data = .Quit
            case "MENU":                      tok._type = .Command; tok.data = .Menu
            case "SAVE":                      tok._type = .Command; tok.data = .Save
            case "GO", "ENTER", "TRAVEL":     tok._type = .Command; tok.data = .Go
            case "LOOK", "EXAMINE":           tok._type = .Command; tok.data = .Look
            case "TAKE":                      tok._type = .Command; tok.data = .Take
            case "INVENTORY", "INV":          tok._type = .Command; tok.data = .Inventory
            case "PLACE", "PUT":              tok._type = .Command; tok.data = .Place
            case "TALK":                      tok._type = .Command; tok.data = .Talk
            case "EXIT", "LEAVE", "VAMOOSE":  tok._type = .Command; tok.data = .Exit
            case "EXITS":                     tok._type = .Command; tok.data = .ListExits
            case "IN", "WITHIN", "INSIDE":    tok._type = .Modifier; tok.data = .Preposition_In
            case "THE":                       tok._type = .Modifier; tok.data = .Article
            case:                             tok._type = .Identifier; tok.data = str
        }
        append(&tokens, tok)
    }
    scan_command_modifiers: for i := 0; i < len(tokens); i +=1  {
        if tokens[i]._type != .Command do continue
        if i+1 == len(tokens) do continue;
        #partial switch tokens[i].data.(ValidCommand) {
            case .Look, .LookInside:
                if tokens[i+1]._type == .Modifier {
                    if tokens[i+1].data.(ModifierType) == .Preposition_In {
                        tokens[i].data = .LookInside
                        ordered_remove(&tokens, i+1);i -= 1
                        continue
                    }
                }
                if tokens[i+1]._type == .Command && tokens[i+1].data.(ValidCommand) == .Inventory {
                    ordered_remove(&tokens, i)
                }
        }
    }
    names, _ := ecs.get_component_list(ge.ctx, Name)
    concat_identifiers: for i := 0; i < len(tokens); i += 1 {
        if tokens[i]._type != .Identifier do continue
        if i+1 == len(tokens) do continue;
        if slice.any_of(names, cast(Name)tokens[i].data.(string)) do continue;
        if tokens[i+1]._type == .Identifier {
            new_name := strings.concatenate([]string{tokens[i].data.(string), " ", tokens[i+1].data.(string)})
            ordered_remove(&tokens, i+1); 
            tokens[i].data = new_name
            i -= 1
            continue
        }
    }

    remove_articles: for i := 0; i < len(tokens); i +=1 {
        if tokens[i]._type != .Modifier do continue
        #partial switch tokens[i].data.(ModifierType) {
            case .Article, .Preposition_At:
                ordered_remove(&tokens, i)
                i -= 1
        }
    }
    return tokens[:]
}

InputTextBuffer :: struct {
    builder:strings.Builder,
    tokens:[dynamic]string, 
};


u8RGB_To_u32_RGB888 :: #force_inline proc (R,G,B:u8) -> u32 {return (cast(u32)R << 16) | (cast(u32)G << 8) | cast(u32)B}

RedOf :: #force_inline proc (hexRGB888:u32) -> u8 {return u8(hexRGB888 >> 16) & 255}
GreenOf :: #force_inline proc (hexRGB888:u32) -> u8 {return u8(hexRGB888 >> 8) & 255}
BlueOf :: #force_inline proc (hexRGB888:u32) -> u8 {return u8(hexRGB888 & 255)}

replace_palette :: proc (target:^sdl2.Surface, current_palette:^[4]u32, new_palette:^[4]u32){
    // uint32_t* pixel_ptr = (`uint32_t*)target.pixels;
    pixel_ptr := cast(^u32)target.pixels
    for i in 0..< target.h * target.w { 
        defer pixel_ptr = mem.ptr_offset(pixel_ptr, 1);
        red, green, blue:u8 = 0, 0, 0;
        sdl2.GetRGB(pixel_ptr^,target.format,&red,&green,&blue);
        detected_colour :u32 = u8RGB_To_u32_RGB888(red,green,blue)
        for colour, j in current_palette{
            replace_color := current_palette[j];
            if detected_colour == replace_color {
                new_color := new_palette[j];
                pixel_ptr^ = sdl2.MapRGB(target.format,RedOf(new_color),GreenOf(new_color),BlueOf(new_color));
            };
        };
    };
};

replace_all_palettes :: proc (using ge:^GlobalEverything, new_room_pal_index:VIEW_ENUM){

    for pal_index in VIEW_ENUM {
        for s in &ge.font_surface_array {
            replace_palette(s, &palettes[view_palettes[pal_index]], &palettes[view_palettes[new_room_pal_index]]);
        };
        for q in &ge.quill_array {
            replace_palette(q, &palettes[view_palettes[pal_index]], &palettes[view_palettes[new_room_pal_index]]);
        };
    };
};

detect_colour :: proc (quad:u32, format:^sdl2.PixelFormat) -> u32 {
    red, green, blue:u8 = 0, 0, 0;
    sdl2.GetRGB(quad,format,&red,&green,&blue);
    return u8RGB_To_u32_RGB888(red,green,blue)
}

handle_text_input :: proc (using ge:^GlobalEverything, event:^sdl2.Event,){
    using text_buffer
    #partial switch event.type {
        case .TEXTINPUT:
            if len(builder.buf) == cap(builder.buf) do return;
            char_to_parse := event.text.text[0];
            if char_to_index(cast(rune)char_to_parse) == -1 do return
            append(&builder.buf, char_to_parse)
        case .KEYDOWN: #partial switch event.key.keysym.sym {
            case .BACKSPACE: strings.pop_byte(&builder)
            case .RETURN:
                for char in &builder.buf do switch char {case 'a'..='z': char -= 32} //make uppercase
                _tokens := strings.split(string(builder.buf[:]), " ", context.temp_allocator)
                for tok in _tokens {
                    append(&tokens, tok)
                }
                for token in tokens {fmt.printf("%s ,", token)}
                strings.builder_reset(&builder)
            }
    }
};

blit_text :: proc (ge:^GlobalEverything, string_to_blit:string, blit_pt:[2]i32){
    space_rect:sdl2.Rect ={
        h = ge.ui.font_rect.h,
        w = ge.ui.font_rect.w,
        y = blit_pt.y,
    }

    for i in 0..<len(string_to_blit){
        space_rect.x = i32(i) * 9 + blit_pt.x;
        char_to_blit_idx := char_to_index(cast(rune)string_to_blit[i])

        if char_to_blit_idx == -1 do continue
        sdl2.BlitSurface(ge.ui.font_surface_array[char_to_blit_idx], nil, ge.working_surface, &space_rect);
    };
};


blit_tile :: proc (using ge:^GlobalEverything, tile:^sdl2.Surface, blit_pt:[2]i32){
    space_rect:= sdl2.Rect{
        h = ui.font_rect.h, 
        w = ui.font_rect.w,
        x = blit_pt.x,
        y = blit_pt.y,
    }
    sdl2.BlitSurface(tile, nil, working_surface, &space_rect);
};

PLAYER_ITEM :: enum {
	AXE,
	LAZARUS_ICON,
	CHRIST_ICON,
	MARY_ICON,
	BAPTIST_ICON,
}

AXE_ItemState :: enum {
	v_CLEARING_StumpwiseLodged,
	i_Default,
}

nil_point :: [2]i32{-1,-1}

Sprite_Points_AXE_ItemState := [AXE_ItemState][2]i32 {
        .i_Default = nil_point,
        .v_CLEARING_StumpwiseLodged = {242, 113},
}

LAZARUS_ICON_ItemState :: enum {
	v_SHRINE_inShrine,
	i_Default,
    i_Broken,
}

Sprite_Points_LAZARUS_ICON_ItemState := [LAZARUS_ICON_ItemState][2]i32 {
    .v_SHRINE_inShrine = {117, 63},
    .i_Default = nil_point,
    .i_Broken = nil_point,
}

PLAYER_ITEM_SpritePoints := [PLAYER_ITEM][][2]i32 {
    .AXE = slice.enumerated_array(&Sprite_Points_AXE_ItemState),
    .LAZARUS_ICON = slice.enumerated_array(&Sprite_Points_LAZARUS_ICON_ItemState),
    .CHRIST_ICON = {},
	.MARY_ICON = {},
	.BAPTIST_ICON = {},
}

PLAYER_ITEM_StateEnums := [PLAYER_ITEM]Maybe(typeid) {
    .AXE = typeid_of(AXE_ItemState),
    .LAZARUS_ICON =  typeid_of(LAZARUS_ICON_ItemState),
    .CHRIST_ICON = nil,
	.MARY_ICON = nil,
	.BAPTIST_ICON = nil,
}

PLAYER_ITEM_synonyms := [PLAYER_ITEM]Synonyms {
    .AXE = {"HATCHET"},
    .LAZARUS_ICON = {"ICON", "LAZARUS"},
	.CHRIST_ICON = {"ICON","JESUS ICON", "JESUS"},
	.MARY_ICON = {"ICON", "THEOTOKOS ICON", "MARY","THEOTOKOS"},
	.BAPTIST_ICON = {"ICON", "JOHN ICON", "BAPTIST ICON", "JOHN THE BAPTIST ICON"},
}

AXE_ItemState_descriptions := [AXE_ItemState] string {
	.v_CLEARING_StumpwiseLodged = "The axe is stumpwise lodged.",
	.i_Default = "A well balanced axe. Much use.",
}

LAZARUS_ICON_ItemState_descriptions := [LAZARUS_ICON_ItemState] string {
	.v_SHRINE_inShrine = "Icon of Lazarus, being raised from the dead.",
	.i_Default = "Icon of Lazarus, being raised from the dead.",
    .i_Broken = "The icon is broken, rotting.",
}

PLAYER_ITEM_descriptions := [PLAYER_ITEM] Descriptions {
	.AXE = cast(Descriptions)slice.enumerated_array(&AXE_ItemState_descriptions),
	.LAZARUS_ICON = {"Icon of Lazarus."},
	.CHRIST_ICON = {"Icon of Christ."},
	.MARY_ICON = {"Icon of the Theotokos."},
	.BAPTIST_ICON = {"Icon of St John the Baptist"},
}

NPC_ENUM :: enum {
    ALEXEI,
}

ALEXEI_ViewState :: enum {
    SKETE_Standing,
}

ALEXEI_TalkGraphicsState :: enum {
    Default,
}

ALEXEI_DialogueState :: enum {
    Default,
    Disappointed,
}

NPC_ENUM_DialogueStateEnums := [NPC_ENUM]typeid {
    .ALEXEI = ALEXEI_DialogueState,
}

Sprite_Points_ALEXEI_ViewState := [ALEXEI_ViewState][2]i32 {
    .SKETE_Standing = {89,58},
}

NPC_ENUM_ViewSpritePoints := [NPC_ENUM][][2]i32 {
    .ALEXEI = slice.enumerated_array(&Sprite_Points_ALEXEI_ViewState),
}

NPC_ENUM_ViewStateEnums := [NPC_ENUM]typeid {
    .ALEXEI = ALEXEI_ViewState,
}


Sprite_Points_ALEXEI_TalkState := [ALEXEI_TalkGraphicsState][2]i32 {
    .Default = {32,20},
}

NPC_ENUM_TalkSpritePoints := [NPC_ENUM][][2]i32 {
    .ALEXEI = slice.enumerated_array(&Sprite_Points_ALEXEI_TalkState),
}

NPC_ENUM_TalkGraphicsStateEnums := [NPC_ENUM]typeid {
    .ALEXEI = typeid_of(ALEXEI_TalkGraphicsState),
}

NPC_ENUM_synonyms := [NPC_ENUM]Synonyms {
    .ALEXEI = {"MAN", "MONK", "GUY"},
}

ALEXEI_descriptions := [ALEXEI_ViewState]string {
    .SKETE_Standing = "Alexei is stern, yet lively. His arms yearn to throw fools into deep, dark pits.",
}

NPC_ENUM_descriptions := [NPC_ENUM] Descriptions {
	.ALEXEI =  cast(Descriptions)slice.enumerated_array(&ALEXEI_descriptions),
}

blit_multiline_string ::  proc (using ge:^GlobalEverything, str:AnimData) {
    new_strings:= make([dynamic]string, 0, 8, context.temp_allocator)
    text  := str.(string)
    LIMIT :: LENGTH_OF_CHAR_BUFFER_ARRAY
    word_search: for len(text) != 0 {
        if len(text) < LIMIT {
            for search_idx in 0..<len(text) {
                if text[search_idx] != '\n' do continue
                cutoff_point := search_idx;
                append(&new_strings, text[: cutoff_point ])
                text = text[cutoff_point+1:len(text)]
                break 
            }
            append(&new_strings, text)
            break word_search
        } 
        for search_idx in 0..<LIMIT {
            if text[search_idx] != '\n' do continue
            append(&new_strings, text[:search_idx])
            text = text[search_idx+1:]
            continue word_search
        }
        cutoff_point: int
        for back_search_idx in 0..<LIMIT { // search backwards for first whitespace
            if text [LIMIT - back_search_idx - 1] != ' ' do continue
            append(&new_strings, text[:LIMIT - back_search_idx])
            text = text[LIMIT - back_search_idx:] // reduce slice
            continue word_search
        }
    }

    for _string, idx in new_strings {
        YPosition: = (NATIVE_HEIGHT) - (ge.ui.font_rect.h * i32(len(new_strings) - idx + 1 ));
        blit_pt := [2]i32{0, YPosition}
        for i in 0..<40{
            tile_blit_point := blit_pt + {cast(i32)i*ge.ui.font_rect.w, 0}
            blit_tile(ge, ui.font_surface_array[char_to_index(' ')], tile_blit_point)
        };
        blit_text(ge, _string, blit_pt)
    }         
} 

blit_top_screen_text :: proc (ge:^GlobalEverything, str:AnimData){
    blit_text(ge, str.(string), {(ge.ui.font_rect.w * 13), 0} ); //NOTE: Needed for the screen position
};

blit_mouse_text :: proc (ge:^GlobalEverything, data:AnimData){
    x := cast(i32)len(data.(string)) * (ge.font_rect.w + 1)
    y := ge.font_rect.h 
    BLIT_PT := MOUSE_PT
    
    if x + MOUSE_PT.x > ge.working_surface.w do BLIT_PT.x -= x
    if y + MOUSE_PT.y > ge.working_surface.h do BLIT_PT.y -= y

    for x in 0..<len(data.(string)) {
        blit_tile(ge, ge.font_surface_array[char_to_index(' ')], BLIT_PT + {cast(i32)x * ge.font_rect.w,0})
    }
    blit_text(ge, data.(string), BLIT_PT ); //NOTE: Needed for the screen position
};

handle_command :: proc (using ge:^GlobalEverything, tokens:[]Token) {
    str:Maybe(string); anim_proc: proc (^GlobalEverything, AnimData)
    defer if str != nil && anim_proc != nil do anim_push(&ge.anim, anim_proc, 240, AnimData(str.(string)));

    switch tokens[0]._type {
        case .Modifier:
        case .Identifier: handle_command(ge, []Token{{.Command, .Look}, {.Identifier, tokens[0].data.(string)}}); return;
        case .Command:
            switch tokens[0].data.(ValidCommand) {
                case .Menu: 
                    mix.PlayChannel(-1, ge.audio.menu[.menu_open], 0)
                    ge.game_mode = .Menu
                case .Save: 
                    ge_to_savedata(ge)
                    savedata_marshall(&ge.save_data, .WRITE_TO_FILE)
                    str = "+GAME SAVED+"
                case .Quit: sdl2.PushEvent(&sdl2.Event{type = .QUIT})
                case .Go:
                    if len(text_buffer.tokens) == 1 {str = "Where would you like to go?";break;};
                    new_index, ok := reflect.enum_from_name(VIEW_ENUM, text_buffer.tokens[1]);
                    switch {
                        case ok && new_index == current_view_enum: str = "You're already here!"
                        case !ok || new_index not_in ge.adjascent_views[current_view_enum]: str = fmt.tprintf( "'%s' isn't near here.",  text_buffer.tokens[1])
                        case view_type[new_index] != .Room: str = "You cannot fit in there!"
                        case ok:
                            for num in &ge.anim.duration do num = 0
                            vd.current_view_enum = new_index
                            vd.current_view_handle = vd.view_entities[new_index]
                            replace_all_palettes(ge, new_index);
                    }
                case .Inventory: ge.game_mode = .Inventory
                case .ListExits:
                    viewnames:= make([dynamic]string, context.temp_allocator)
                    for view in VIEW_ENUM {
                        if view_type[view] == .LookInside do continue
                        if view in adjascent_views[ge.current_view_enum] do append(&viewnames, reflect.enum_string(view))
                    }
                    gronk := strings.join(viewnames[:], ", ", context.temp_allocator)
                    str = strings.concatenate({"Current exits:\n", gronk}, context.temp_allocator)
                case .Look: 
                    if len(tokens) == 1 {
                        str = "What would you like to look at?"
                        break
                    }
                    h1, h2, h3, h4 : []ecs.Entity = 
                        {ge.current_view_handle}, 
                        vd.scenery_items.entities[current_view_enum][:],
                        slice.enumerated_array(&ge.pid.pi_entities),
                        slice.enumerated_array(&ge.npc.entities)

                    handles := slice.concatenate([][]ecs.Entity{h1, h2, h3, h4}, context.temp_allocator)
                    names := transmute([]string)ecs.get_component_slice_values(ctx, handles, Name)

                    context.user_ptr = &tokens[1].data.(string)
                    i, ok := slice.linear_search_proc(names[:], proc(n:string) -> bool {return (cast(^string)context.user_ptr)^ == n})
                    if !ok {str = fmt.tprintf("Cannot find the '%s'.", tokens[1].data.(string));break};
                    _type := ecs.get_comp(ge.ctx, handles[i], _EntityType)
                    switch _type^ {
                        case .PlayerItem, .NPC:
                            loc := ecs.get_comp(ge.ctx, handles[i], Location)^
                            ok = loc == ge.current_view_enum
                            if !ok {str = fmt.tprintf("Cannot find the '%s'.", tokens[1].data.(string));break};
                            fallthrough;
                        case .SceneryItem, .View: 
                            handle := handles[i]
                            desc := ecs.get_comp(ge.ctx, handle, Descriptions)
                            state := ecs.get_comp(ge.ctx, handle, StateInt)
                            str = desc[state^]
                    }
                case .LookInside:
                    if len(tokens) == 1 {str = "What would you like to look inside?";break;}
                    new_index, ok := reflect.enum_from_name(VIEW_ENUM, tokens[1].data.(string));
                    if !ok {str = fmt.tprintf("Cannot find the '%s'.", tokens[1].data.(string));break};
                    if new_index in vd.adjascent_views[current_view_enum] {
                        current_view_enum = new_index  
                        current_view_handle = vd.view_entities[new_index] 
                        break 
                    } 
                    str = "Can't look inside that."
                case .Exit:
                    if vd.immediate_exit[current_view_enum] == nil {
                        str = "There are no obvious exits."; break;   
                    }
                    current_view_handle = vd.view_entities[vd.immediate_exit[current_view_enum].(VIEW_ENUM)] 
                    current_view_enum = vd.immediate_exit[current_view_enum].(VIEW_ENUM)  
                case .Take:
                    h1, h2, h3 : []ecs.Entity = 
                        {ge.current_view_handle}, 
                        vd.scenery_items.entities[current_view_enum][:],
                        slice.enumerated_array(&ge.pid.pi_entities) 

                    handles := slice.concatenate([][]ecs.Entity{h1, h2, h3}, context.temp_allocator)
                    names := transmute([]string)ecs.get_component_slice_values(ctx, handles, Name)
        
                    context.user_ptr = &tokens[1].data.(string)
                    i, ok := slice.linear_search_proc(names[:], proc(n:string) -> bool {return (cast(^string)context.user_ptr)^ == n})

                    if !ok {str = fmt.tprintf("Cannot find the '%s'.", tokens[1].data.(string));break};
                    _type := ecs.get_comp(ge.ctx, handles[i], _EntityType)
                    switch _type^ {
                        case .SceneryItem: str = "Wouldn't be a good idea to take that." // POLISH: Personalized for each item you can try to take.
                        case .View: str = "Would be nice to take a place with you, but it cannot be done."
                        case .NPC: str = "You will have to keep them in your memories."
                        case .PlayerItem:
                            loc := ecs.get_comp(ge.ctx, handles[i], Location)^
                            ok = loc == ge.current_view_enum
                            if !ok {str = fmt.tprintf("Cannot find the '%s'.", tokens[1].data.(string));break};
                            _e_idx, ok := slice.linear_search(slice.enumerated_array(&ge.pid.pi_entities), handles[i])
                            err := ge.pid.take_events[cast(PLAYER_ITEM)_e_idx](ge)
                            switch err {
                                case .InventoryFull: str = "Inventory full."
                                case .ItemNotInLocation: str = "What are you doing Kris"
                                case .NO_ERROR: str = fmt.tprintf("'%v' taken.", names[i])
                            }
                    }
                case .Place:
                    handles: []ecs.Entity = slice.enumerated_array(&ge.pid.pi_entities) 
                    names := transmute([]string)ecs.get_component_slice_values(ctx, handles, Name)
        
                    context.user_ptr = &tokens[1].data.(string)
                    i, ok := slice.linear_search_proc(names[:], proc(n:string) -> bool {return (cast(^string)context.user_ptr)^ == n})

                    if !ok {str = fmt.tprintf("You don't have a '%s'.", tokens[1].data.(string));break};
                    if len(tokens) == 2 {str = "Where would you like to place it?"; break;}
                    _e_idx, _ := slice.linear_search(slice.enumerated_array(&ge.pid.pi_entities), handles[i])
                    err := ge.pid.place_events[cast(PLAYER_ITEM)_e_idx](ge, tokens[2])
                    switch err {
                        case .NOT_APPLICABLE_TARGET: str = fmt.tprintf("Cannot place your '%v' there.", tokens[1].data.(string)) // POLISH
                        case .NO_ERROR: str = fmt.tprintf("'%v' placed.", tokens[1].data.(string)) // POLISH
                    }
                case .Talk:
                    handles: []ecs.Entity = slice.enumerated_array(&ge.npc.entities) 
                    names := transmute([]string)ecs.get_component_slice_values(ctx, handles, Name)
                    context.user_ptr = &tokens[1].data.(string)
                    i, ok := slice.linear_search_proc(names[:], proc(n:string) -> bool {return (cast(^string)context.user_ptr)^ == n})

                    if !ok {str = fmt.tprintf("'%s' is not here.", tokens[1].data.(string));break};
                    npc.dialoguing_npc, _ = reflect.enum_from_name(NPC_ENUM, names[i])
                    dialogue_state := ecs.get_comp(ge.ctx, handles[i], DialogueStateInt)
                    npc.current_node = npc.dialogue_start[npc.dialoguing_npc.(NPC_ENUM)][dialogue_state^]
                    ge.game_mode = .Dialogue
                case .Invalid:
            }
            switch tokens[0].data.(ValidCommand) {
                case .ListExits, .Look, .Take, .LookInside, .Exit, .Place, .Go: if str != nil do anim_proc = blit_multiline_string
                case .Save: anim_proc = blit_top_screen_text
                case .Invalid, .Inventory, .Menu, .Quit, .Talk:
            }
    }

}

make_working_surface :: #force_inline proc (render_surface:^sdl2.Surface) -> ^sdl2.Surface {
    return sdl2.CreateRGBSurface(0, 
        NATIVE_WIDTH, NATIVE_HEIGHT, 
        i32(render_surface.format.BitsPerPixel), u32(render_surface.format.Rmask), 
        render_surface.format.Gmask, render_surface.format.Bmask, render_surface.format.Amask);
}
import ecs "odin-ecs"

Views :: struct {
    ids:[VIEW_ENUM]ecs.Entity,
}




_ECSRef :: struct {
    ctx:^ecs.Context,
}

VIEW_ENUM_descriptions := [VIEW_ENUM] Descriptions {
	.CHURCH = {"Dedicated to Saint Lazarus, this modest Church stands strong."},
	.CLEARING = {"A quiet clearing. A good place to find lazy trees."},
	.SKETE = {"It is a sturdy, cozy skete."},
	.CHAPEL = {"PLACEHOLDER CHAPEL DESCRIPTION"},
	.SHRINE = {"Almost like a miniature church, the shrine keeps travellers hopes in a travel-sized temple."},
}

CHURCH_SceneryItems :: enum {
    SHRINE,
    TREE,
    GATE,
}

CHURCH_SceneryItems_descriptions := [CHURCH_SceneryItems] Descriptions {
    .SHRINE = {"The shrine stands tall on the hill, proud of its older brother."},
    .TREE = {"It is a bare tree, standing alone."},
    .GATE = {"Crudely drawn, and unfinished."},
}

CLEARING_SceneryItems :: enum {
    TREES,
    STUMP,
}

CLEARING_STUMP_ItemState :: enum {
	Default,
	AxewiseStuck,
}

CLEARING_STUMP_ItemState_descriptions := [CLEARING_STUMP_ItemState] string {
	.Default = "Stump left behind from an old tree.Memories of childhood return.",
	.AxewiseStuck = "The stump is axewise stuck.",
}

CLEARING_SceneryItems_descriptions := [CLEARING_SceneryItems] Descriptions {
    .TREES = {"Loitering in the clearing, the trees don't have much to do."},
    .STUMP = cast(Descriptions)slice.enumerated_array(&CLEARING_STUMP_ItemState_descriptions),
}

SHRINE_SceneryItems :: enum {
    CANDLE,
}

SHRINE_SceneryItems_descriptions := [SHRINE_SceneryItems] Descriptions {
    .CANDLE = {"A sleeping soldier of metal and oil waits for its next call to duty." },
}

VIEW_SceneryItemDescriptions := [VIEW_ENUM][]Descriptions {
    .SHRINE = slice.enumerated_array(&SHRINE_SceneryItems_descriptions),
    .CHURCH = slice.enumerated_array(&CHURCH_SceneryItems_descriptions),
    .CLEARING = slice.enumerated_array(&CLEARING_SceneryItems_descriptions),
    .SKETE = nil,
    .CHAPEL = nil,
}

VIEW_SCENERY_ITEM_enums := [VIEW_ENUM]typeid {
    .CHURCH = CHURCH_SceneryItems,
    .CLEARING = CLEARING_SceneryItems,
    .SHRINE = SHRINE_SceneryItems,
    .SKETE = nil,
    .CHAPEL = nil,
}

SceneryItemData :: struct {
    entities:[VIEW_ENUM][dynamic]ecs.Entity,
}

_ViewData :: struct {
    view_palettes:[VIEW_ENUM]PALETTE,
    view_entities:[VIEW_ENUM]ecs.Entity,
    view_type:[VIEW_ENUM]ViewType,
    adjascent_views:[VIEW_ENUM]bit_set[VIEW_ENUM],
    immediate_exit:[VIEW_ENUM]Maybe(VIEW_ENUM),
    current_view_handle: ecs.Entity, 
    current_view_enum: VIEW_ENUM,
    scenery_items:SceneryItemData, //thonk
};

char_to_index :: proc (_input:rune) -> int{
	input := int(_input)

	switch {
		case input >= 'A' && input <= 'Z': return input - 'A'
		case input >= '0' && input <= '9': return 26 + input - '0'
		case input >= 'a' && input <= 'z': return 36 + input - 'a'
	}
    switch(input){
        case '+': return 62;
        case ' ': return 63;
        case '?': return 64;
        case '!': return 65;
        case ',': return 66;
        case '.': return 67;
        case '\'': return 68;
        case '"': return 69;
        case: return -1;
    };
};

index_to_char :: proc (_input:int) -> rune {
    input := cast(u8)_input
	switch {
        case input >= 0 && input <= 25 : return rune('A' + input)
        case input >= 26 && input <= 35 : return rune('0' + input - 26)
        case input >= 36 && input <= 62 : return rune('a' + input - 36) 
	}

    switch(input){
        case 62: return '+';
        case 63: return ' ';
        case 64: return '?';
        case 65: return '!';
        case 66: return ',';
        case 67: return '.';
        case 68: return '\'';
        case 69: return '"';
        case: return 255;
    };
}
 
_UIData :: struct {
    font_surface_array:[70]^sdl2.Surface,
    font_rect: sdl2.Rect,
    quill_array:[4]^sdl2.Surface,
}

_EntityType :: enum {
    View,
    SceneryItem,
    PlayerItem,
    NPC,
}

TakeError :: enum {
    NO_ERROR,
    InventoryFull,
    ItemNotInLocation,
}

PlaceError :: enum {
    NO_ERROR,
    NOT_APPLICABLE_TARGET,
}

import "core:c/libc"

Settings :: struct {
    quit:bool,
    window_size:int,
}

PALETTE :: enum {
    Church, Clearing, Skete,
}

PlayerItemData :: struct {
    pi_entities:[PLAYER_ITEM]ecs.Entity,
    inv:[dynamic]PLAYER_ITEM, // Cap 12
    take_events:[PLAYER_ITEM]proc(^GlobalEverything) -> TakeError,
    place_events:[PLAYER_ITEM]proc(^GlobalEverything, Token) -> PlaceError,
}

NPCData :: struct {
    entities:[NPC_ENUM]ecs.Entity,
    dialoguing_npc:Maybe(NPC_ENUM),
    dialogue_start:[NPC_ENUM][]^DialogueNode,
    current_node: ^DialogueNode,
}

CutsceneData :: struct {
    current_cutscene: proc (^GlobalEverything, CoroInt) -> CoroInt,
    coro_int:CoroInt,
}


Savedata_SceneryItem :: struct {
    state_int:[]StateInt,
}

SavedataIntermediate :: struct {
    game_progress:GameProgress,
    current_view_enum: VIEW_ENUM,
    window_size:int,
    player_items: struct {
        state_int:[]StateInt, // will implicitly be length of PLAYER_ITEM
        location:[]Location,
    },
    npc: struct {
        state_int:[]StateInt, // will implicitly be length of NPC_ENUM
        dialogue_state_int:[]DialogueStateInt,
        location:[]Location,
    },
    viewdata: struct {
        state_int:[]StateInt,
        scenery_item_data: []Savedata_SceneryItem,
    },
    inventory: struct {
            len:int,
    items:[]PLAYER_ITEM,
    }, 
}

SAVEGAME_IO :: enum {
    READ_FROM_FILE,
    WRITE_TO_FILE,
};

init_savedata :: proc (sd:^SavedataIntermediate, coro_int:CoroInt) -> CoroInt {
    switch coro_int {
        case 0:
            sd.player_items.location = make([]Location, len(PLAYER_ITEM))
            sd.player_items.state_int = make([]StateInt, len(PLAYER_ITEM))
        
            sd.npc.location = make([]Location, len(NPC_ENUM))
            sd.npc.dialogue_state_int = make([]DialogueStateInt, len(NPC_ENUM)) 
            sd.npc.state_int = make([]StateInt, len(NPC_ENUM)) 
            
            sd.viewdata.state_int = make([]StateInt, len(VIEW_ENUM))
            sd.viewdata.scenery_item_data = make([]Savedata_SceneryItem, len(VIEW_ENUM))
            for x, i in &sd.viewdata.scenery_item_data {
                _enum := VIEW_SCENERY_ITEM_enums[cast(VIEW_ENUM)i] 
                if _enum == nil do continue
                x.state_int = make([]StateInt, len(reflect.enum_field_names(_enum)))
            }
            return 1
        case 1:
            sd.inventory.items = make([]PLAYER_ITEM, sd.inventory.len)
            return -1
    }
    return -1
}

savedata_marshall :: proc (sd:^SavedataIntermediate, mode:SAVEGAME_IO){ // For file io
    io_func := mode == .WRITE_TO_FILE ? os.write : os.read

    saveFileHandle, err := os.open("save.dat", mode == .WRITE_TO_FILE ? os.O_WRONLY : os.O_RDONLY);

    io_func(saveFileHandle, mem.any_to_bytes(sd.game_progress));
    io_func(saveFileHandle, mem.any_to_bytes(sd.current_view_enum));
    io_func(saveFileHandle, mem.any_to_bytes(sd.window_size));
    init_savedata_coro:= CoroInt(0)
    if mode == .READ_FROM_FILE {
        delete(sd.player_items.location);
        delete(sd.player_items.state_int)

        delete(sd.npc.location)
        delete(sd.npc.state_int) 
        delete(sd.npc.dialogue_state_int) 

        delete(sd.viewdata.state_int)
        delete(sd.viewdata.scenery_item_data)

        for x, i in &sd.viewdata.scenery_item_data {
            _enum := VIEW_SCENERY_ITEM_enums[cast(VIEW_ENUM)i] 
            if _enum == nil do continue
            delete(x.state_int)
        }
        init_savedata_coro = init_savedata(sd, init_savedata_coro)
    }
    for v_idx in PLAYER_ITEM {
        io_func(saveFileHandle, mem.any_to_bytes(sd.player_items.state_int[v_idx]))
    }
    for v_idx in PLAYER_ITEM {
        io_func(saveFileHandle, mem.any_to_bytes(sd.player_items.location[v_idx]))
    }

    for n_idx in NPC_ENUM {
        io_func(saveFileHandle, mem.any_to_bytes(sd.npc.state_int[n_idx]))
    }

    for n_idx in NPC_ENUM {
        io_func(saveFileHandle, mem.any_to_bytes(sd.npc.dialogue_state_int[n_idx]))
    }

    for v_idx in NPC_ENUM {
        io_func(saveFileHandle, mem.any_to_bytes(sd.npc.location[v_idx]))
    }

    for v_idx in VIEW_ENUM {
        io_func(saveFileHandle, mem.any_to_bytes(sd.viewdata.state_int[v_idx]))
    }
    for v_idx in VIEW_ENUM {
        _enum := VIEW_SCENERY_ITEM_enums[v_idx]
        if _enum == nil do continue 
        for _int, idx in &sd.viewdata.scenery_item_data[v_idx].state_int {
            io_func(saveFileHandle, mem.any_to_bytes(_int))
        }
    }

    io_func(saveFileHandle, mem.any_to_bytes(sd.inventory.len))
   
    if mode == .READ_FROM_FILE {
        delete(sd.inventory.items)
        init_savedata_coro = init_savedata(sd, init_savedata_coro)
    }
    
    for slot in &sd.inventory.items {
        io_func(saveFileHandle, mem.any_to_bytes(slot))
    }

    os.close(saveFileHandle);
};

savedata_to_ge :: proc (ge:^GlobalEverything, sd:^SavedataIntermediate) {
    ge.game_progress = sd.game_progress
    ge.current_view_enum = sd.current_view_enum
    ge.current_view_handle = ge.view_entities[ge.current_view_enum]
    ge.settings.window_size = sd.window_size
    for id, idx in ge.pid.pi_entities {
        ecs.set_components(ge.ctx, id, sd.player_items.location[idx], sd.player_items.state_int[idx])
    }
    clear(&ge.pid.inv)
    for item in sd.inventory.items {
        append(&ge.pid.inv, item)
    }
    for id, idx in ge.npc.entities {
        ecs.set_components(ge.ctx, id, sd.npc.location[idx], sd.npc.state_int[idx], sd.npc.dialogue_state_int[idx])
    }
    for id, v_idx in ge.view_entities {
        ecs.set_component(ge.ctx, id, sd.viewdata.state_int[v_idx])
        _enum := VIEW_SCENERY_ITEM_enums[cast(VIEW_ENUM)v_idx]
        if _enum == nil do continue 
        for _id, _idx in ge.scenery_items.entities[v_idx] {
            ecs.set_component(ge.ctx, 
                _id, 
                sd.viewdata.scenery_item_data[v_idx].state_int[_idx])
        }
    }
}

ge_to_savedata :: proc (ge:^GlobalEverything) {
    scenery_item_savedata:[VIEW_ENUM]Savedata_SceneryItem
    for x, v_idx in &scenery_item_savedata {
        _enum := VIEW_SCENERY_ITEM_enums[v_idx]
        if _enum == nil do continue
        x.state_int = ecs.get_component_slice_values(ge.ctx, ge.scenery_items.entities[v_idx][:], StateInt)
        assert(len(x.state_int) == len(reflect.enum_field_names(_enum)))
    }

    ge.save_data = {
        game_progress = ge.game_progress,
        current_view_enum = ge.current_view_enum,
        window_size = ge.settings.window_size,
        player_items = {
            location = ecs.get_component_slice_values(ge.ctx, slice.enumerated_array(&ge.pid.pi_entities), Location),
            state_int = ecs.get_component_slice_values(ge.ctx, slice.enumerated_array(&ge.pid.pi_entities), StateInt),
        },
        inventory = {
            len = len(ge.pid.inv),
            items = slice.clone(ge.pid.inv[:]) ,
        },
        npc = {
            location = ecs.get_component_slice_values(ge.ctx, slice.enumerated_array(&ge.npc.entities), Location),
            state_int = ecs.get_component_slice_values(ge.ctx, slice.enumerated_array(&ge.npc.entities), StateInt),
            dialogue_state_int = ecs.get_component_slice_values(ge.ctx, slice.enumerated_array(&ge.npc.entities), DialogueStateInt),
        },
        viewdata = {
            state_int =  ecs.get_component_slice_values(ge.ctx, slice.enumerated_array(&ge.view_entities), StateInt),
            scenery_item_data = slice.clone(slice.enumerated_array(&scenery_item_savedata)),
        },
    }

}

MenuAudio :: enum {
    menu_open,
    menu_cursor_change,
    menu_quit,
}

GlobalEverything :: struct {
    audio: struct {
        menu: [MenuAudio]^mix.Chunk,
    },
    window:^sdl2.Window,
    game_mode:GameMode,
    game_progress:GameProgress,
    csd:CutsceneData,
    frame_counter:u64,
    working_surface:^sdl2.Surface,
    render_surface:^sdl2.Surface,
    palettes:[PALETTE][4]u32,
    using settings:Settings,
    ctx:^ecs.Context,
    using ui:_UIData,
    using vd:_ViewData,
    anim:Animations,
    text_buffer:InputTextBuffer,
    pid:PlayerItemData, 
    npc:NPCData,
    save_data:SavedataIntermediate,
    right_clicked_entity:Maybe(ecs.Entity),
    right_clicked_origin:[2]i32,
}

un_underscore :: proc (s:string) -> string {
    newstring, _ := strings.replace_all(s, "_", " ")
    return newstring
}

re_underscore :: proc (s:string) -> string {
    newstring, _ := strings.replace_all(s, " ", "_")
    return newstring
}

dialogue_node_make :: proc (dialogue_text:string, parent_node:^DialogueNode = nil, selection_option:string = "", event:proc(^GlobalEverything) = nil) -> ^DialogueNode {
    new_node := new(DialogueNode)
    new_node.selection_option = selection_option
    new_node.dialogue_text = dialogue_text
    new_node.parent_node = parent_node
    new_node.event_if_chosen = event
    return new_node
}

DialogueNode :: struct {
    selection_option:string,// 
    dialogue_text:string,
    parent_node:^DialogueNode,
    child_nodes:[dynamic]^DialogueNode,
    event_if_chosen: proc (^GlobalEverything),
};

dialogue_init :: proc (ge:^GlobalEverything) {
    alexei_start := dialogue_node_make("Your time is nigh.\n...Repent!")
    alexei_second := dialogue_node_make("...Else into the hole with you!", alexei_start)
    alexei_third_1:= dialogue_node_make(
        "Yes, hole.\nThe deep hole has many sharp bits. It will be hard to fish you out.",
        alexei_second,
        "Hole?")
    alexei_third_2 := dialogue_node_make(
        "Alexei shakes his head. \"You're already in deep.\"", 
        alexei_second, 
        "I'm not repenting.",
        proc (ge:^GlobalEverything) {
            ecs.set_component(ge.ctx, ge.npc.entities[.ALEXEI], cast(DialogueStateInt)ALEXEI_DialogueState.Disappointed)
        })

    alexei_dialogue:[4]^DialogueNode = {alexei_start, alexei_second, alexei_third_1, alexei_third_2};

    init_dialogue_nodes :: proc (nodes:[]^DialogueNode){
        for node in nodes {
            node.child_nodes = make_dynamic_array([dynamic]^DialogueNode)
            if node.parent_node == nil do continue;
            child_node_index := len(node.parent_node.child_nodes);
            append(&node.parent_node.child_nodes, node)
        };
    };
    init_dialogue_nodes(alexei_dialogue[:])

    ge.npc.dialogue_start[.ALEXEI][0] = alexei_dialogue[0]

    alexei_disappointed := dialogue_node_make("Alexei cannot bear to look at you.")

    ge.npc.dialogue_start[.ALEXEI][1] = alexei_disappointed
}

ecs_components_init :: proc (ge:^GlobalEverything) {
    for id, v_idx in &ge.vd.view_entities {
        id = ecs.create_entity(ge.ctx)
        ecs.add_component(ge.ctx, id, cast(Name)reflect.enum_string(v_idx))
        ecs.add_component(ge.ctx, id, cast(StateInt)0)
        ecs.add_component(ge.ctx, id, _EntityType.View)
        ecs.add_component(ge.ctx, id, VIEW_ENUM_descriptions[v_idx])
        desc_slice := make([]^sdl2.Surface, 1)
        desc_slice[0] = sdl2.LoadBMP(fmt.ctprintf("assets/%s.bmp", reflect.enum_string(v_idx)))
        surf, _ := ecs.add_component(ge.ctx, id, cast(Surfaces)desc_slice);
        _enum := VIEW_SCENERY_ITEM_enums[v_idx] 
        if _enum == nil do continue
        for zip, case_idx in reflect.enum_fields_zipped(_enum) {
            entity_id := ecs.create_entity(ge.ctx)
            append(&ge.vd.scenery_items.entities[v_idx], entity_id)
            ecs.add_component(ge.ctx, entity_id, cast(StateInt)0)
            ecs.add_component(ge.ctx, entity_id, _EntityType.SceneryItem)
            ecs.add_component(ge.ctx, entity_id, cast(Name)zip.name)
            ecs.add_component(ge.ctx, entity_id, VIEW_SceneryItemDescriptions[v_idx][cast(int)zip.value])
        }
        
    }

    for e_pi in PLAYER_ITEM {
        id := ecs.create_entity(ge.ctx)
        ge.pid.pi_entities[e_pi] = id
        ecs.add_component(ge.ctx, id, cast(StateInt)0)
        ecs.add_component(ge.ctx, id, Location(nil))
        ecs.add_component(ge.ctx, id, cast(Name)un_underscore(reflect.enum_string(e_pi)))
        ecs.add_component(ge.ctx, id, _EntityType.PlayerItem)
        ecs.add_component(ge.ctx, id, PLAYER_ITEM_synonyms[e_pi])
        ecs.add_component(ge.ctx, id, PLAYER_ITEM_descriptions[e_pi])

        for x in PLAYER_ITEM_StateEnums {
            if x == nil do continue
            enum_names := reflect.enum_field_names(x.(typeid))
            slice := make([]^sdl2.Surface, len(enum_names))
            for name, idx in enum_names {
                filename := fmt.ctprintf("assets/%v_%s.bmp", e_pi, name[2:])
                slice[idx] = sdl2.LoadBMP(filename)
                if slice[idx] == nil do continue
                slice[idx].clip_rect.x = PLAYER_ITEM_SpritePoints[e_pi][idx].x
                slice[idx].clip_rect.y = PLAYER_ITEM_SpritePoints[e_pi][idx].y
            }
            ecs.add_component(ge.ctx, id, Surfaces(slice))
        }
    }

    ecs.set_component(ge.ctx, ge.pid.pi_entities[.AXE], Location(.CLEARING))
    ecs.set_component(ge.ctx, ge.pid.pi_entities[.AXE], StateInt(AXE_ItemState.v_CLEARING_StumpwiseLodged))

    for e_npc in NPC_ENUM {
        id := ecs.create_entity(ge.ctx)
        ge.npc.entities[e_npc] = id
        ecs.add_component(ge.ctx, id, cast(StateInt)0)
        ecs.add_component(ge.ctx, id, cast(TalkGraphicsStateInt)0)
        ecs.add_component(ge.ctx, id, cast(DialogueStateInt)0)
        ecs.add_component(ge.ctx, id, _EntityType.NPC)
        ecs.add_component(ge.ctx, id, cast(Name)un_underscore(reflect.enum_string(e_npc)))
        ecs.add_component(ge.ctx, id, NPC_ENUM_synonyms[e_npc])
        ecs.add_component(ge.ctx, id, NPC_ENUM_descriptions[e_npc])
        ecs.add_component(ge.ctx, id, Location(nil))

        
        for x in NPC_ENUM_ViewStateEnums {
            if x == nil do continue
            enum_names := reflect.enum_field_names(x)
            slice := make([]^sdl2.Surface, len(enum_names))
            for name, idx in enum_names {
                filename := fmt.ctprintf("assets/%v_%s.bmp", e_npc, name)
                slice[idx] = sdl2.LoadBMP(filename)
                if slice[idx] == nil do continue
                slice[idx].clip_rect.x = NPC_ENUM_ViewSpritePoints[e_npc][idx].x
                slice[idx].clip_rect.y = NPC_ENUM_ViewSpritePoints[e_npc][idx].y
            }
            ecs.add_component(ge.ctx, id, Surfaces(slice))
        }

        for x in NPC_ENUM_TalkGraphicsStateEnums {
            if x == nil do continue
            enum_names := reflect.enum_field_names(x)
            slice := make([]^sdl2.Surface, len(enum_names))
            for name, idx in enum_names {
                filename := fmt.ctprintf("assets/%v_TALK_%s.bmp", e_npc, name)
                slice[idx] = sdl2.LoadBMP(filename)
                if slice[idx] == nil do continue
                slice[idx].clip_rect.x = NPC_ENUM_TalkSpritePoints[e_npc][idx].x
                slice[idx].clip_rect.y = NPC_ENUM_TalkSpritePoints[e_npc][idx].y
            }
            ecs.add_component(ge.ctx, id, TalkSurfaces(slice))
        }

        for x, n_idx in NPC_ENUM_DialogueStateEnums {
            if x == nil do continue
            ge.npc.dialogue_start[n_idx] = make([]^DialogueNode, len(reflect.enum_field_names(x)))
        }
    }
    ecs.set_component(ge.ctx, ge.npc.entities[.ALEXEI], Location(.SKETE))
}

font_surface_init :: proc (ge:^GlobalEverything) {
    for i, idx in &ge.ui.font_surface_array { if idx == 63 do break
        i = sdl2.LoadBMP(fmt.ctprintf("assets/font/%v.bmp", index_to_char(idx)));
    }
    ge.ui.font_surface_array[char_to_index('+')] = sdl2.LoadBMP(cstring("assets/font/+.bmp"));
    ge.ui.font_surface_array[char_to_index(' ')] = sdl2.LoadBMP(cstring("assets/font/space.bmp"));
    ge.ui.font_surface_array[char_to_index('?')] = sdl2.LoadBMP(cstring("assets/font/question_mark.bmp"));
    ge.ui.font_surface_array[char_to_index('!')] = sdl2.LoadBMP(cstring("assets/font/exclamation_mark.bmp"));
    ge.ui.font_surface_array[char_to_index(',')] = sdl2.LoadBMP(cstring("assets/font/comma.bmp"));
    ge.ui.font_surface_array[char_to_index('.')] = sdl2.LoadBMP(cstring("assets/font/period.bmp"));
    ge.ui.font_surface_array[char_to_index('\'')] = sdl2.LoadBMP(cstring("assets/font/apostrophe.bmp"));
    ge.ui.font_surface_array[char_to_index('"')] = sdl2.LoadBMP(cstring("assets/font/quotation_double.bmp"));
    ge.ui.font_rect = ge.ui.font_surface_array[0].clip_rect

    for x, idx in &ge.ui.quill_array do x = sdl2.LoadBMP(fmt.ctprintf("assets/quill/quill_%c.bmp", '1' + idx));
}

item_events_init :: proc (ge:^GlobalEverything) {
    event_take_axe :: proc (ge:^GlobalEverything) -> TakeError {
        h := ge.pid.pi_entities[.AXE]
        if ecs.get_comp(ge.ctx, h, Location)^ != Location(.CLEARING) do return .ItemNotInLocation
        if len(ge.pid.inv) == 12 do return .InventoryFull
        append(&ge.pid.inv, PLAYER_ITEM.AXE)
        ecs.set_component(ge.ctx, h, Location(nil)) 
        ecs.set_component(ge.ctx, ge.pid.pi_entities[.AXE], cast(StateInt)AXE_ItemState.i_Default)
        ecs.set_component(ge.ctx, ge.scenery_items.entities[.CLEARING][CLEARING_SceneryItems.STUMP], cast(StateInt)CLEARING_STUMP_ItemState.Default)
        return .NO_ERROR
    }

    event_place_axe :: proc (ge:^GlobalEverything, target:Token) -> PlaceError {
        if target.data != "STUMP" do return .NOT_APPLICABLE_TARGET

        h := ge.pid.pi_entities[.AXE]
        idx, ok := slice.linear_search(ge.pid.inv[:], PLAYER_ITEM.AXE)
        ordered_remove(&ge.pid.inv, idx)
        ecs.set_component(ge.ctx, h, Location(.CLEARING)) 
        ecs.set_component(ge.ctx, ge.pid.pi_entities[.AXE], cast(StateInt)AXE_ItemState.v_CLEARING_StumpwiseLodged)
        ecs.set_component(ge.ctx, ge.scenery_items.entities[.CLEARING][CLEARING_SceneryItems.STUMP], cast(StateInt)CLEARING_STUMP_ItemState.AxewiseStuck)
        return .NO_ERROR
    }

    ge.pid.take_events[.AXE] = event_take_axe
    ge.pid.place_events[.AXE] = event_place_axe
}

main :: proc (){

    when MULTITHREADING {
        pool:thread.Pool;
        thread.pool_init(&pool, context.allocator, 4)
        thread.pool_start(&pool)
    }

    ctx := ecs.init_ecs()
    ge := GlobalEverything {

        ctx = &ctx,
        game_mode = .MainMenu,
        game_progress = .Fresh,
        csd = {
            coro_int = -1,
        },
        settings = {
            window_size = 3,
        },
        vd = {
            immediate_exit = {
                .SHRINE = .CHURCH,
                .CHURCH = nil,
                .CLEARING = nil,
                .SKETE = nil,
                .CHAPEL = .SKETE,
            },
            view_type = {
                .CHAPEL = .Room,
                .CHURCH = .Room,
                .SHRINE = .LookInside,
                .CLEARING = .Room,
                .SKETE = .Room,
            },
            adjascent_views = {
                .SHRINE = {.CHURCH},
                .CHURCH = {.CLEARING, .SHRINE},
                .CLEARING = {.CHURCH, .SKETE},
                .SKETE = {.CLEARING, .CHAPEL},
                .CHAPEL = {.SKETE},
            },
            view_palettes = {
                .CHURCH = .Church, 
                .CLEARING = .Clearing, 
                .SKETE = .Skete, 
                .CHAPEL = .Skete, 
                .SHRINE = .Church, 
            },
        },
        palettes =  {
            .Church = [4]u32{0xCBF1F5, 0x445975, 0x0E0F21, 0x050314},
            .Clearing = [4]u32{0xEBE08D, 0x8A7236, 0x3D2D17, 0x1A1006},
            .Skete = [4]u32{0x8EE8AF, 0x456E44, 0x1D2B19, 0x0B1706},
        },
        pid = {
            inv = make([dynamic]PLAYER_ITEM, 0, 6),
        },
    }

    if mix.OpenAudio(44100, mix.DEFAULT_FORMAT, 2, 2048) < 0 {
        fmt.printf("Mixer couldn't init, error: %v \n", mix.GetError())
    }

    for idx in MenuAudio {
        ge.audio.menu[idx] = mix.LoadWAV(fmt.ctprintf("assets/sound/%v.wav", reflect.enum_string(idx)))
    }


    strings.builder_init_len_cap(&ge.text_buffer.builder, 0, 35)
    ecs_components_init(&ge)
    dialogue_init(&ge)
    item_events_init(&ge)
    font_surface_init(&ge)

    init_savedata(&ge.save_data, 0)
    init_savedata(&ge.save_data, 1)
    saveFileHandle, err := os.open("save.dat", os.O_RDONLY)
    fresh_game := err == os.ERROR_FILE_NOT_FOUND;
    if fresh_game {
            newFile, err := os.open("save.dat", os.O_CREATE); os.close(newFile)
            savedata_marshall(&ge.save_data, .WRITE_TO_FILE)
    }

    if sdl2.Init( sdl2.INIT_VIDEO ) < 0 {
        fmt.printf( "SDL could not initialize! SDL_Error: %s\n", sdl2.GetError() );
        return;
    } 

    ge.window = sdl2.CreateWindow("Searching for the Name", 
       	sdl2.WINDOWPOS_UNDEFINED,	sdl2.WINDOWPOS_UNDEFINED, 
        i32(NATIVE_WIDTH * ge.settings.window_size), 
        i32(NATIVE_HEIGHT * ge.settings.window_size), 
        sdl2.WINDOW_SHOWN );
    if ge.window == nil {
        fmt.printf( "Window could not be created! SDL_Error: %s\n", sdl2.GetError());
        return ;
    };

    ge.render_surface = sdl2.GetWindowSurface(ge.window);
    ge.working_surface = make_working_surface(ge.render_surface)

    GAME_LOOP: for ge.quit != true {
        blacken_surf(ge.working_surface)
        frameStart := sdl2.GetTicks(); ge.frame_counter += 1;

        sdl2.StartTextInput(); 
        event:sdl2.Event;
        saved_kb_event:sdl2.Event
        saved_kb_event_ui:sdl2.Event
        saved_mouse_event:sdl2.Event
        HANDLE_INPUT: for( sdl2.PollEvent( &event ) != false ){
            if event.type == .QUIT {ge.settings.quit = true;break;};
            when PROFILING {
                if event.type == .KEYDOWN {
                    if event.key.keysym.sym == .F1 {
                    total := slice.reduce(profiling_ms[:], 0.0, proc(a,b:f64) -> f64 {return b > 1.0 ? a : a + b})
                    average := total / cast(f64)len(profiling_ms)
                    fmt.printf("%v-THREADING: For %v samples, average time is %v ms. ",  MULTITHREADING ? "MULTI-" : "SINGLE-", len(profiling_ms), average,)
                    fmt.printf("Number of >0.2 ms spikes: %v \n", slice.count_proc(profiling_ms[:], proc(a:f64) -> bool {return a > 0.2} ))
                    clear(&profiling_ms)
                    }
                }
            }
            
            if event.type == .KEYDOWN do saved_kb_event_ui = event;
            if event.type == .KEYDOWN do saved_kb_event = event;
            if event.type == .MOUSEBUTTONDOWN do saved_mouse_event = event;
            if event.type == .MOUSEMOTION {
                MOUSE_PT = {event.motion.x / cast(i32)ge.settings.window_size, event.motion.y / cast(i32)ge.settings.window_size}
            }
            switch ge.game_mode {
                case .Default: 
                    handle_text_input(&ge, &event);
                case .Dialogue, .Inventory, .Menu, .MainMenu, .Cutscene, .RightClickMenu:
            }
        };

        if len(ge.text_buffer.tokens) > 0 {
            tokens := parse_tokens(&ge, ge.text_buffer.tokens[:])
            handle_command(&ge, tokens);
            clear(&ge.text_buffer.tokens);
        }
        
       switch ge.game_mode {
            case .MainMenu,  .Cutscene:
            case .Default, .Dialogue, .Inventory, .Menu, .RightClickMenu:
                sdl2.BlitSurface(ecs.get_comp(ge.ctx,ge.vd.current_view_handle, Surfaces)^[0], nil, ge.working_surface, nil); 
  
                @static entity_surfs :[dynamic]^sdl2.Surface; defer clear(&entity_surfs)
                @static entity_ids :[dynamic]ecs.Entity; defer clear(&entity_ids)
                for x in PLAYER_ITEM {
                    handle := ge.pid.pi_entities[x]
                    loc := ecs.get_comp(ge.ctx, handle, Location)
                    if loc^ == nil || loc^.(VIEW_ENUM) != ge.current_view_enum do continue
                    s, i, _ := ecs.get_components(ge.ctx, handle, Surfaces, StateInt)
                    if s[i^] == nil do continue
                    sdl2.BlitSurface(s[i^], nil, ge.working_surface, &s[i^].clip_rect);
                    append(&entity_surfs, s[i^])
                    append(&entity_ids, handle)
                }
            
                for x in NPC_ENUM {
                    handle := ge.npc.entities[x]
                    loc := ecs.get_comp(ge.ctx, handle, Location)
                    if loc^ == nil || loc^.(VIEW_ENUM) != ge.current_view_enum do continue
                    
                    s, i, _ := ecs.get_components(ge.ctx, handle, Surfaces, StateInt)
                    if s[i^] == nil do continue

                    sdl2.BlitSurface(s[i^], nil, ge.working_surface, &s[i^].clip_rect);
                    append(&entity_surfs, s[i^])
                    append(&entity_ids, handle)
                }
                if ge.game_mode == .RightClickMenu do break
                @static highlight_entities := false
    
                if saved_kb_event_ui.key.keysym.sym == .LCTRL do highlight_entities = !highlight_entities;
                if saved_kb_event_ui.key.keysym.sym == .LCTRL do fmt.printf("ctrl pressed \n")
                if highlight_entities {
                    blit_top_screen_text(&ge, "Highlighting Items")

                    surroundings := make([dynamic][2]i32); defer delete(surroundings)
                    current_palette := ge.palettes[ge.view_palettes[ge.current_view_enum]]
    
                    @static logged_framecount := u64(0); 
                    @static colour_highlight := 0;
        
                    switch {
                        case ge.frame_counter - logged_framecount > 15: 
                            colour_highlight = 0
                            logged_framecount = ge.frame_counter
                        case ge.frame_counter - logged_framecount == 15: 
                            colour_highlight = colour_highlight == 3 ? 0 : colour_highlight + 1
                            logged_framecount = ge.frame_counter
                    }
        
                    blit_colour := current_palette[colour_highlight]
    
                    when PROFILING do profile_time := profile_start();
                    for surf in entity_surfs {
                        when MULTITHREADING {
                            highlight_surf_threaded(&ge, surf, blit_colour, &pool)
                        } else {
                            highlight_surf(&ge, surf, blit_colour)
                        }
                    }
                    when PROFILING {
                        time_end := profile_end(profile_time)
                        append(&profiling_ms, time_end)
                    }
                }   

                if len(entity_ids) > 0 && saved_mouse_event.button.type == .MOUSEBUTTONDOWN {
                    if saved_mouse_event.button.button == sdl2.BUTTON_LEFT {
                        fmt.printf("Button binary: %8b \n", saved_mouse_event.button.button)
                        rect_pt_ul := [2]i32{entity_surfs[0].clip_rect.x, entity_surfs[0].clip_rect.y}
                        rect_pt_br := rect_pt_ul + [2]i32{entity_surfs[0].clip_rect.w, entity_surfs[0].clip_rect.h}
                        fmt.printf("Mouse click %v, ul %v, br %v \n", MOUSE_PT, rect_pt_ul, rect_pt_br)
                        fmt.printf("tile h %v tile w %v \n", ge.font_rect.h, ge.font_rect.w )
                        if point_within_bounds(MOUSE_PT, rect_pt_ul, rect_pt_br) {
                            anim_push(&ge.anim, blit_mouse_text, 120, cast(string)ecs.get_comp(ge.ctx, entity_ids[0], Name)^)
                        }
                    }
                    if saved_mouse_event.button.button == sdl2.BUTTON_LEFT {
                        fmt.printf("Button binary: %8b \n", saved_mouse_event.button.button)

                        rect_pt_ul := [2]i32{entity_surfs[0].clip_rect.x, entity_surfs[0].clip_rect.y}
                        rect_pt_br := rect_pt_ul + [2]i32{entity_surfs[0].clip_rect.w, entity_surfs[0].clip_rect.h}
                        fmt.printf("Mouse click %v, ul %v, br %v \n", MOUSE_PT, rect_pt_ul, rect_pt_br)

                        if point_within_bounds(MOUSE_PT, rect_pt_ul, rect_pt_br) {
                            ge.right_clicked_entity = entity_ids[0];
                            ge.game_mode = .RightClickMenu
                            ge.right_clicked_origin = MOUSE_PT
                        }
                    }
                }

        }

        switch ge.game_mode {
            case .MainMenu: render_main_menu_mode(&ge, &saved_kb_event)
            case .Default: render_default(&ge);
            case .Menu: render_menu_mode(&ge, &saved_kb_event)
            case .Inventory: render_inventory_mode(&ge, &saved_kb_event)
            case .Dialogue: render_dialogue_mode(&ge, &saved_kb_event)
            case .RightClickMenu: render_right_click_menu_mode(&ge, &saved_mouse_event)
            case .Cutscene: ge.csd.coro_int = ge.csd.current_cutscene(&ge, ge.csd.coro_int)
        }

        if ge.game_mode != .Cutscene {
            anims_advance_one(&ge, &ge.anim)
        }

        BLIT_WORKING_SURFACE: {
            sdl2.BlitScaled(ge.working_surface, nil, ge.render_surface, nil);
            sdl2.UpdateWindowSurface(ge.window);
            frameTime := sdl2.GetTicks() - frameStart;
            if frameDuration > frameTime do sdl2.Delay(frameDuration - frameTime);
        }
    };
    sdl2.Quit();
    return ;
}
