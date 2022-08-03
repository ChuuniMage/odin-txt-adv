package main

import "core:fmt";
import "core:strings";
import "core:slice";
import "core:os";
import "vendor:sdl2";

NATIVE_WIDTH :: 320
NATIVE_HEIGHT :: 200

LENGTH_OF_CHAR_BUFFER_ARRAY :: 36
LENGTH_OF_QUILL_ARRAY :: 4

MAX_NUMBER_OF_SCENERY_ITEMS :: 16
MAX_INVENTORY_ITEMS :: 16
MAX_NUMBER_OF_SYNONYMS :: 8

Point_i32 :: struct {
    x:i32,
    y:i32,
}

PALETTE :: enum {
    Church, Clearing, Skete,
}

VIEW_ENUMS :: enum {
	CHURCH, CLEARING, SKETE, CHAPEL, SHRINE,
}

ViewType :: enum {
    Room, LookInside,
}

ValidCommand :: enum  {
    Quit,
    Menu,
    Invalid,
    Save,
    Go,
    Look,
    Take,
    Place,
    Inventory,
    Talk,
    ListExits,
    Exit,
};

GameMode :: enum {
    _Default,
    _Menu,
    _Inventory,
    _Dialogue,
    _LookInside,
};
GlobalSurfaces :: struct {
    working_surface:^sdl2.Surface ,
    font_surface_array:[96]^sdl2.Surface,
    view_background_surfaces:[VIEW_ENUMS]^sdl2.Surface,
    quill_array:[LENGTH_OF_QUILL_ARRAY]^sdl2.Surface,
    // Better solution needed, to get rid of dead data? Irrelevant for now?
    item_in_view_surfaces:[PLAYER_ITEM][VIEW_ENUMS]^sdl2.Surface, // should be dynamic array of {VIEW_ENUM, PLAYER_ITEM, STATE_INT}
    item_points_in_view:[PLAYER_ITEM][VIEW_ENUMS]Point_i32,
    npc_portraits:[NPC_ENUM]^sdl2.Surface,
    npc_standing:[NPC_ENUM]^sdl2.Surface,
    font_rect: sdl2.Rect,
};

GameSettings :: struct {
    window_size:int, // default = 1
    quit:bool, // default = false
};

SceneryItemData :: struct {
    item_name:[MAX_NUMBER_OF_SCENERY_ITEMS]string,
    item_descriptions:[MAX_NUMBER_OF_SCENERY_ITEMS][dynamic]string,
    synonyms:[MAX_NUMBER_OF_SCENERY_ITEMS][MAX_NUMBER_OF_SYNONYMS]string, // To be put into another struct
    current_description:[MAX_NUMBER_OF_SCENERY_ITEMS]int, //Redundant with item state
    number_of_items:int, //Redundant with dynarray
};

ViewData :: struct {
    current_view_idx: VIEW_ENUMS, 
    npc_in_room:[VIEW_ENUMS]Maybe(NPC_ENUM),
    npc_description:[NPC_ENUM]string,
    scenery_items:[VIEW_ENUMS]SceneryItemData, //thonk
    events:[VIEW_ENUMS]EventData,
    view_type:[VIEW_ENUMS]ViewType,
    adjascent_views:[VIEW_ENUMS]bit_set[VIEW_ENUMS], // adjascent_views[view_to_query][is_this_adjascent]
    adjascent_views_num:[VIEW_ENUMS]int, // This and the above could be refactored as dynamic array
};

//TODO: child nodes as dynamic array

DialogueNode :: struct {
    selection_option:string,// 
    dialogue_text:string,
    parent_node:^DialogueNode,
    child_nodes:[dynamic]^DialogueNode,
};

Text_RenderState :: struct {
    current_txt_anim: proc (int, ^GlobalSurfaces, string) -> int,
    duration_count:int,
    string_to_blit:string, // Is this needed with future allocator stuff?
};

Inventory_RenderState :: struct{
    left_column_selected: bool,
    row_selected:int,
};

Menu_RenderState :: struct {
    res_option_index,  prev_res_option_index, selected_option_index :int,
};


NPC_RenderState :: struct {
    current_npc:NPC_ENUM,
    current_node:^DialogueNode,
    selected_dialogue_option, number_of_options:int,
};

GlobalRenderStates :: struct {
     txt: Text_RenderState,
     inv:Inventory_RenderState,
     menu:Menu_RenderState,
     npc:NPC_RenderState,
};

GlobalEverything :: struct {
    settings:GameSettings,
    surfs:GlobalSurfaces,
    view_data:ViewData,
    game_mode:GameMode,
    palettes:[PALETTE][4]u32,
    room_palettes:[VIEW_ENUMS]^[4]u32,
    dialogue_data:DialogueData,
    item_state:Item_State,
    render_states:GlobalRenderStates,
    save_data:_SaveData,
};

render_dialogue :: proc (using ge:^GlobalEverything){
    using render_states.npc, surfs
    portrait:= npc_portraits[current_npc]; 
    sdl2.BlitSurface(portrait, nil, working_surface, &portrait.clip_rect);
    blit_general_string(0, &surfs, current_node.dialogue_text)
    if number_of_options <= 1 do return;
    for i in 0..<number_of_options {
        YPosition := (NATIVE_HEIGHT) - (font_rect.h * i32(number_of_options - (i*2) + 8 ));
        tile_to_blit := font_surface_array[char_to_index(cast(u8)' ')]
        blit_tile(tile_to_blit,LENGTH_OF_CHAR_BUFFER_ARRAY + 4, working_surface, YPosition, font_rect.w * 18);
        blit_tile(tile_to_blit,LENGTH_OF_CHAR_BUFFER_ARRAY + 4, working_surface, YPosition - font_rect.h, font_rect.w * 18);
        blit_text(&surfs, current_node.child_nodes[i].selection_option, YPosition, font_rect.w * 20);
    };
    plus_x_pos := font_rect.w * 18;
    plus_y_pos := (NATIVE_HEIGHT) - (font_rect.h * i32(number_of_options - (selected_dialogue_option*2) + 8 ));

    blit_text(&surfs, "+", plus_y_pos, plus_x_pos);
};

render_menu :: proc (using ge:^GlobalEverything, ){
    using ge.render_states
    context.allocator = context.temp_allocator
    for Y in 0..<10 {
        blit_tile(surfs.font_surface_array[char_to_index(u8(' '))],24,surfs.working_surface, surfs.font_rect.h* i32(Y), 0);
    };
    res_option_str:[5]string = {"1", "2", "3", "4", "5"};
    resolutionMessage:string = strings.concatenate({"  WINDOW SCALE x", res_option_str[menu.res_option_index]})

    blit_text(&surfs, resolutionMessage, surfs.font_rect.h * 1, 0);
    blit_text(&surfs, "  SAVE", surfs.font_rect.h * 3, 0);
    blit_text(&surfs, "  QUIT", surfs.font_rect.h * 9, 0);
    blit_text(&surfs, "+",
        surfs.font_rect.h * (menu.selected_option_index == 2 ? 9 :i32(menu.selected_option_index * 2 + 1)), 
        surfs.font_rect.w);
};

inventory_get_nth_item :: proc (using inv:^PlayerInventory, position_in_list:int) -> (PLAYER_ITEM, bool){
    if inv.origin_index == -1 do return nil, false
    current_item := inv.inv_item[inv.origin_index];
    for  i in  0..<inv.number_of_items_held {
        if i == position_in_list do return current_item.item_enum, true
        if current_item.next_item_index == -1 do return nil, false
        current_item = inv.inv_item[current_item.next_item_index];
    };
    return nil, false
};

render_inventory :: proc (using ge:^GlobalEverything, ){
    for Y in 0..<8 {
        blit_tile(surfs.font_surface_array[char_to_index(u8(' '))],36,surfs.working_surface, surfs.font_rect.h* i32(Y), 0);
    };
    using ge.item_state
    if (player_inv.number_of_items_held > 0){
        for i in 0..< MAX_ITEMS_IN_INVENTORY / 2 {
            if(player_inv.occupied[i] == true){
                item_name: = reflect.enum_string(player_inv.inv_item[i].item_enum);
                blit_text(&surfs, item_name, surfs.font_rect.h * i32(i), surfs.font_rect.w * 3);
            };
            if(player_inv.occupied[i+(MAX_ITEMS_IN_INVENTORY / 2)] == true){
                item_name := reflect.enum_string(player_inv.inv_item[i + (MAX_ITEMS_IN_INVENTORY / 2)].item_enum);
                blit_text(&surfs, item_name, surfs.font_rect.h * i32(i), surfs.font_rect.w * 20);
            };
        };
    };

    selected_item_in_inventory_index := #force_inline proc(using render_states:^GlobalRenderStates) -> int {
        switch{
            case inv.row_selected == (MAX_ITEMS_IN_INVENTORY / 2): return -1
            case inv.left_column_selected: return inv.row_selected
            case: return inv.row_selected + (MAX_ITEMS_IN_INVENTORY / 2)
        }
    }(&ge.render_states)

    selected_item_enum, ok := inventory_get_nth_item(&player_inv, selected_item_in_inventory_index);

    if ok { using player_items;
        current_desc_idx := current_description[selected_item_enum]
        blit_general_string(1, &surfs, item_descriptions[selected_item_enum][current_desc_idx])
    }
    
    blit_text(&surfs, "  EXIT INVENTORY", surfs.font_rect.h * (MAX_ITEMS_IN_INVENTORY / 2), 0);
    using ge.render_states
    plus_x_pos :i32 = surfs.font_rect.h * i32(inv.row_selected) ;
    plus_y_pos :i32 = inv.left_column_selected ? surfs.font_rect.w : surfs.font_rect.w * 17; 
    blit_text(&surfs, "+", plus_x_pos, plus_y_pos);
};


render_default := proc (using ge:^GlobalEverything, text_buffer:^InputTextBuffer) {
    using surfs
    if view_data.npc_in_room[view_data.current_view_idx] != nil { // Blit NPC
        npc_surface := npc_standing[view_data.npc_in_room[view_data.current_view_idx].(NPC_ENUM)];
        sdl2.BlitSurface(npc_surface, nil, working_surface, &npc_surface.clip_rect);
    }
    using render_states.txt
    if current_txt_anim != nil {
        duration_count = current_txt_anim(duration_count, &surfs, string_to_blit);
        if duration_count == -1 do mem.zero_item(&render_states.txt)
    } 
    if text_buffer.elems_in_charBuffer == 0 do return

    using text_buffer
    blit_tile(font_surface_array[char_to_index(u8(' '))],len(charBuffer) + 4, working_surface, (font_rect.h * -1) + NATIVE_HEIGHT, 0);
    blit_text(&surfs, string(charBuffer[:]), (font_rect.h * -1) + NATIVE_HEIGHT, 0);

    animate_quill :: proc (using gs:^GlobalSurfaces, elems_in_charBuffer:int){
        @static animation_frame := 0;
        @static counter := 0;
        counter += 1
        if (counter == 30) {
            animation_frame = animation_frame == 3 ? 0 : animation_frame + 1;
            counter = 0;
        };
        blit_tile(
            quill_array[animation_frame],
            1, working_surface, 
            i32((quill_array[0].clip_rect.h * -1) + NATIVE_HEIGHT), 
            i32((quill_array[0].clip_rect.w + 1) * i32(elems_in_charBuffer)));
    };
    if text_buffer.elems_in_charBuffer != 35 do animate_quill(&ge.surfs, text_buffer.elems_in_charBuffer);   
}



init_scenery_items :: proc (using view_data:^ViewData){
    add_scenery_item :: proc (using scenery_items:^SceneryItemData, name:string, description:string){
        assert(number_of_items <= 16)
        idx := number_of_items;
        item_name[idx] = name
        item_descriptions[idx] = make([dynamic]string)
        append(&item_descriptions[idx], description)
        number_of_items += 1;
    }
    add_scenery_item_description :: proc (using scenery_items:^SceneryItemData, name:string, description:string) {
        idx, _ := scenery_item_name_to_index(name, scenery_items)
        current_num_of_descs:= len(scenery_items.item_descriptions[idx])
        append(&item_descriptions[idx], description)
    }

    add_scenery_item(&scenery_items[.CHURCH], "CHURCH", "Dedicated to Saint Lazarus, this modest Church stands strong.");
    add_scenery_item(&scenery_items[.CHURCH], "SHRINE", "The shrine stands tall on the hill, proud of its older brother.");
    add_scenery_item(&scenery_items[.CHURCH], "TREE", "It is a bare tree, standing alone.");
    add_scenery_item(&scenery_items[.CHURCH], "GATE", "Crudely drawn, and unfinished.");

    add_scenery_item(&scenery_items[.CLEARING], "CLEARING", "A quiet clearing. A good place to find lazy trees.");
    add_scenery_item(&scenery_items[.CLEARING], "TREES", "Loitering in the clearing, the trees don't have much to do." );
    add_scenery_item(&scenery_items[.CLEARING], "STUMP", "The stump is axewise stuck.");
    add_scenery_item_description(&scenery_items[.CLEARING], "STUMP", "Stump left behind from an old tree. Memories of childhood return.");

    add_scenery_item(&scenery_items[.SHRINE], "SHRINE", "Almost like a miniature church, the shrine keeps travellers hopes in a travel-sized temple.");
    add_scenery_item(&scenery_items[.SHRINE], "CANDLE", "A sleeping soldier of metal and oil waits for its next call to duty.");
};

init_npc_descriptions :: proc (vd:^ViewData){  
    vd.npc_description[.ALEXEI] = "Alexei is stern, yet lively. His arms yearn to throw fools into deep, dark pits."
};

init_surfaces :: proc (using surfs:^GlobalSurfaces) {
    context.allocator = context.temp_allocator
    for x, idx in view_background_surfaces {
        temp_dir := fmt.aprintf("assets/%s.bmp", reflect.enum_string(idx));
        view_background_surfaces[idx] = sdl2.LoadBMP(strings.clone_to_cstring(temp_dir));
    };
    for i in 0..=25 {
        temp_dir := fmt.aprintf("assets/font/cap_%c.bmp", 'A' + i);
        font_surface_array[char_to_index('A' + i)] = sdl2.LoadBMP(strings.clone_to_cstring(temp_dir));
    };
    for i in 0..=25 {
        temp_dir := fmt.aprintf("assets/font/low_%c.bmp", 'a' + i);
        font_surface_array[char_to_index('a' + i)] = sdl2.LoadBMP(strings.clone_to_cstring(temp_dir));
    };
    for i in 0..<10 {
        temp_dir := fmt.aprintf("assets/font/%c.bmp", '0' + i);
        font_surface_array[char_to_index('0' + i)] = sdl2.LoadBMP(strings.clone_to_cstring(temp_dir));
    };
    font_surface_array[char_to_index(cast(u8)' ')] = sdl2.LoadBMP(strings.clone_to_cstring("assets/font/space.bmp"));
    font_surface_array[char_to_index(cast(u8)'+')] = sdl2.LoadBMP(strings.clone_to_cstring("assets/font/+.bmp"));
    font_surface_array[char_to_index(cast(u8)'?')] = sdl2.LoadBMP(strings.clone_to_cstring("assets/font/question_mark.bmp"));
    font_surface_array[char_to_index(cast(u8)'!')] = sdl2.LoadBMP(strings.clone_to_cstring("assets/font/exclamation_mark.bmp"));
    font_surface_array[char_to_index(cast(u8)',')] = sdl2.LoadBMP(strings.clone_to_cstring("assets/font/comma.bmp"));
    font_surface_array[char_to_index(cast(u8)'.')] = sdl2.LoadBMP(strings.clone_to_cstring("assets/font/period.bmp"));
    font_surface_array[char_to_index(cast(u8)'\'')] = sdl2.LoadBMP(strings.clone_to_cstring("assets/font/apostrophe.bmp"));
    font_surface_array[char_to_index(cast(u8)'"')] = sdl2.LoadBMP(strings.clone_to_cstring("assets/font/quotation_double.bmp"));
    for x, idx in &quill_array {
        temp_dir := fmt.aprintf("assets/quill/quill_%c.bmp", '1' + idx);
        x = sdl2.LoadBMP(strings.clone_to_cstring(temp_dir));
    };
    for x, item_idx in item_in_view_surfaces {
        for _x, view_idx in x {
            temp_dir := fmt.aprintf( "assets/%s_item_%s.bmp", reflect.enum_string(view_idx), reflect.enum_string(item_idx));
            item_in_view_surfaces[item_idx][view_idx] = sdl2.LoadBMP(strings.clone_to_cstring(temp_dir));
            if item_in_view_surfaces[item_idx][view_idx] == nil do continue
            switch(reflect.enum_string(item_idx)){
                case "AXE":
                    item_in_view_surfaces[item_idx][view_idx].clip_rect.x = 242;
                    item_in_view_surfaces[item_idx][view_idx].clip_rect.y = 113;
                case "LAZARUS_ICON":
                    item_in_view_surfaces[item_idx][view_idx].clip_rect.x = 117;
                    item_in_view_surfaces[item_idx][view_idx].clip_rect.y = 63;
            }
        };
    };
    default_npc_portrait_point :: proc (npc:NPC_ENUM) -> Point_i32{
        switch (npc){
            case .ALEXEI: return {32,20};
            case: return {0,0};
        };
    };
    
    default_npc_standing_point :: proc (npc:NPC_ENUM) -> Point_i32{
        switch (npc){
            case .ALEXEI: return {89,58};
            case: return {0,0};
        };
    };
    for x, idx in &npc_portraits {
        temp_dir := fmt.aprintf("assets/%s_PORTRAIT.bmp", reflect.enum_string(idx));
        npc_portraits[idx] = sdl2.LoadBMP(strings.clone_to_cstring(temp_dir))
        if(npc_portraits[idx] != nil){
            point := default_npc_portrait_point(idx);
            npc_portraits[idx].clip_rect.x = point.x;
            npc_portraits[idx].clip_rect.y = point.y;
        };
        temp_dir = fmt.aprintf("assets/%s_STANDING.bmp", reflect.enum_string(idx));
        npc_standing[idx] = sdl2.LoadBMP(strings.clone_to_cstring(temp_dir))
        if(npc_standing[idx] != nil){
            point := default_npc_standing_point(idx);
            npc_standing[idx].clip_rect.x = point.x;
            npc_standing[idx].clip_rect.y = point.y;
        };
    };
    font_rect = font_surface_array[0].clip_rect
}


global_buffer: [4*mem.Kilobyte]byte
global_arena: mem.Arena

init_everything :: proc (using ge:^GlobalEverything) {
    
    palettes = {
        .Church = [4]u32{0xCBF1F5, 0x445975, 0x0E0F21, 0x050314},
        .Clearing = [4]u32{0xEBE08D, 0x8A7236, 0x3D2D17, 0x1A1006},
        .Skete = [4]u32{0x8EE8AF, 0x456E44, 0x1D2B19, 0x0B1706},
    }

    room_palettes = {
        .CHURCH = &ge.palettes[.Church], 
        .CLEARING = &ge.palettes[.Clearing], 
        .SKETE = &ge.palettes[.Skete], 
        .CHAPEL = &ge.palettes[.Skete], 
        .SHRINE = &ge.palettes[.Church], 
    };
	settings.quit = false
	settings.window_size = 1

	view_data.current_view_idx = .CHURCH

    view_data.adjascent_views_num[.SHRINE] = 1;
    view_data.adjascent_views[.SHRINE] = {.CHURCH}

    view_data.adjascent_views_num[.CHURCH] = 2;
    view_data.adjascent_views[.CHURCH] = {.CLEARING, .SHRINE}

    view_data.adjascent_views_num[.CLEARING] = 2;
    view_data.adjascent_views[.CLEARING] = {.CHURCH, .SKETE}

    view_data.adjascent_views_num[.SKETE] = 2;
    view_data.adjascent_views[.SKETE] = {.CLEARING, .CHAPEL}

    view_data.adjascent_views_num[.CHAPEL] = 1;
    view_data.adjascent_views[.CHAPEL] = {.SKETE}

    for x in &view_data.npc_in_room { x = nil }
    view_data.npc_in_room[.SKETE] = .ALEXEI

    for x in &view_data.view_type { x = .Room }
    view_data.view_type[.SHRINE] = .LookInside

    view_data.view_type = {
        .CHAPEL = .Room,
        .CHURCH = .Room,
        .SHRINE = .LookInside,
        .CLEARING = .Room,
        .SKETE = .Room,
    }

    init_scenery_items(&view_data);
    init_npc_descriptions(&view_data);
    init_surfaces(&surfs)

    // Done
	game_mode = ._Default




    init_player_item_data(&item_state, &ge.view_data);
    render_states.inv.left_column_selected = true
}

parse_token :: proc(str:string) -> ValidCommand {
	switch str {
		case "QUIT": return .Quit
		case "MENU": return .Menu
		case "SAVE": return .Save
		case "GO", "ENTER", "TRAVEL": return .Go
		case "LOOK", "EXAMINE": return .Look
		case "TAKE": return .Take
		case "INVENTORY", "INV": return .Inventory
		case "PLACE", "PUT": return .Place
		case "TALK": return .Talk
		case "EXITS": return .ListExits
		case: return .Invalid
	}
};

LENGTH_OF_TOKEN_ARRAY :: 18

InputTextBuffer :: struct {
    elems_in_charBuffer:int,
    charBuffer:[LENGTH_OF_CHAR_BUFFER_ARRAY]u8,
    tokenBuffer:[]string, 
};

import "core:mem"
import "core:reflect"

char_to_index :: proc (_input:union{u8, int}) -> int{

	input :int
	switch v in _input {
		case int: input = _input.(int)
		case u8: input = int(_input.(u8))
	}
	switch {
		case input >= 'A' && input <= 'Z': return input - 'A'
		case input >= '0' && input <= '9': return 26 + input - '0'
		case input >= 'a' && input <= 'z': return 36 + input - 'a'
	}
    switch(input){
        case ' ':return 62;
        case '+': return 63;
        case '?': return 64;
        case '!': return 65;
        case ',': return 66;
        case '.': return 67;
        case '\'': return 68;
        case '"': return 69;
        case: return -1;
    };
};

NPC_ENUM :: enum {
    ALEXEI,
}

DialogueData :: struct {
    starter_nodes:[NPC_ENUM]^DialogueNode,
};

PLAYER_ITEM :: enum {
    AXE,
    LAZARUS_ICON,
    CHRIST_ICON,
    MARY_ICON,
    JBAPTIST_ICON,
}

InventoryItem_ListElem :: struct {
    item_enum:PLAYER_ITEM,
    next_item_index:i8, // -1 = tail
};

MAX_ITEMS_IN_INVENTORY :: 12

PlayerInventory :: struct {
    inv_item:[MAX_ITEMS_IN_INVENTORY]InventoryItem_ListElem,
    occupied:[MAX_ITEMS_IN_INVENTORY]bool,
    tail_index:i8,
    origin_index:i8,
    number_of_items_held:int,
};

PlayerItemData :: struct {
    item_descriptions:[PLAYER_ITEM][dynamic]string,
    synonyms:[PLAYER_ITEM][MAX_NUMBER_OF_SYNONYMS]string,
    current_description:[PLAYER_ITEM]int,
    is_takeable_item:bit_set[PLAYER_ITEM], // Probably handle-able with unique item enum states?
    is_item_taken:bit_set[PLAYER_ITEM],
    current_room_location:[PLAYER_ITEM]Maybe(VIEW_ENUMS),
    number_of_items_in_view:[VIEW_ENUMS]int,
    index_within_inventory:[PLAYER_ITEM]i8,
};

PlaceEvent :: struct {
    scenery_dest_index:int,
    event:proc (^PlayerItemData, ^SceneryItemData),
};


EventData :: struct {
    //These will very likely need to be made multi-dimensional.
    take_events:[PLAYER_ITEM]proc (^PlayerItemData, ^SceneryItemData),
    place_events:[PLAYER_ITEM]PlaceEvent,
};

Item_State :: struct {
    player_inv:PlayerInventory,
    player_items:PlayerItemData,
    events:EventData,
};

check_item_synonyms :: proc (str:string, pid:^PlayerItemData) -> (PLAYER_ITEM, bool) {
    for i, idx in pid.synonyms {
        for j in 0..<MAX_NUMBER_OF_SYNONYMS {
            if str == pid.synonyms[idx][j] do return idx, true
        };
    };
    return nil, false
};

item_name_to_index :: proc (str:string, pid:^PlayerItemData) -> (item_enum:PLAYER_ITEM, ok:bool) {
    item_enum, ok = reflect.enum_from_name(PLAYER_ITEM, str)
    if(ok){
        return item_enum, ok
    }
    return check_item_synonyms(str, pid)
};

scenery_item_name_to_index :: proc (name:string, scenery_items:^SceneryItemData) -> (idx:int, ok:bool){
    for  i in 0..=scenery_items.number_of_items {
        if name == scenery_items.item_name[i] do return i, true
    };
    return -1, false
};

handle_savedata :: proc (save_data:^_SaveData, ge:^GlobalEverything, mode:SAVEGAME_IO) {
    reverse_copy :: proc "contextless" (dst, src: rawptr, len: int) -> rawptr {
        return mem.copy(src, dst, len)
    }
    order_func := mode == .WRITE ?  mem.copy : reverse_copy

    order_func(&save_data.res_index, &ge.render_states.menu.res_option_index, 1)

    order_func(&save_data.view_data.current_view_idx, &ge.view_data.current_view_idx, 1)
    order_func(&save_data.view_data.npc_in_room, &ge.view_data.npc_in_room, 1)
    for desc, idx in &save_data.view_data.scenery_items {
        order_func(&desc.current_description, &ge.view_data.scenery_items[idx].current_description, 1)
    }
    order_func(&save_data.view_data.adjascent_views, &ge.view_data.adjascent_views, 1)
    order_func(&save_data.view_data.adjascent_views_num, &ge.view_data.adjascent_views_num, 1)

    for idx in 0..<MAX_ITEMS_IN_INVENTORY {
        order_func(&save_data.player_inventory.inv_item[idx], &ge.item_state.player_inv.inv_item[idx], 1)
        order_func(&save_data.player_inventory.occupied[idx], &ge.item_state.player_inv.occupied[idx], 1)
    }
    order_func(&save_data.player_inventory.number_of_items_held, &ge.item_state.player_inv.number_of_items_held, 1)
    order_func(&save_data.player_inventory.origin_index, &ge.item_state.player_inv.origin_index, 1)
    order_func(&save_data.player_inventory.tail_index, &ge.item_state.player_inv.tail_index, 1)
    
    for idx in PLAYER_ITEM {
        order_func(&save_data.item_data.current_description[idx], &ge.item_state.player_items.current_description[idx], 1)
        order_func(&save_data.item_data.current_room_location[idx], &ge.item_state.player_items.current_room_location[idx], 1)
        order_func(&save_data.item_data.index_within_inventory[idx], &ge.item_state.player_items.index_within_inventory[idx], 1)
    }
    order_func(&save_data.item_data.is_takeable_item, &ge.item_state.player_items.is_takeable_item, 1)
    order_func(&save_data.item_data.is_item_taken, &ge.item_state.player_items.is_item_taken, 1)
    for idx in VIEW_ENUMS {
        order_func(&save_data.item_data.number_of_items_in_view[idx], &ge.item_state.player_items.number_of_items_in_view[idx], 1)
    }
    
}

_SaveData :: struct {
    res_index:int,
    view_data: struct {
        current_view_idx:VIEW_ENUMS,
        npc_in_room:[VIEW_ENUMS]Maybe(NPC_ENUM),
        scenery_items:[VIEW_ENUMS] struct {
            current_description:[MAX_NUMBER_OF_SCENERY_ITEMS]u8,
        },
        adjascent_views:[VIEW_ENUMS]bit_set[VIEW_ENUMS],
        adjascent_views_num:[VIEW_ENUMS]int, // Can this be derived from the number of 1s in the above?
    },
    item_data: struct {
        current_description:[PLAYER_ITEM]int,
        is_takeable_item:bit_set[PLAYER_ITEM], 
        is_item_taken:bit_set[PLAYER_ITEM],
        current_room_location:[PLAYER_ITEM]Maybe(VIEW_ENUMS),
        number_of_items_in_view:[VIEW_ENUMS]int,
        index_within_inventory:[PLAYER_ITEM]int,
    },
    player_inventory: PlayerInventory,

}

SAVEGAME_IO :: enum {
    READ,
    WRITE,
};

handle_savegame_io :: proc (mode:SAVEGAME_IO, save_data:^_SaveData){

    io_func := mode == .WRITE ? os.write : os.read

    saveFileHandle, err := os.open("save.dat", mode == .WRITE ? os.O_WRONLY : os.O_RDONLY);
    items_handled := 0;
    errno:os.Errno

    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.res_index));
    
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.item_data.index_within_inventory));
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.item_data.is_item_taken));
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.item_data.is_takeable_item));
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.item_data.current_description));
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.item_data.number_of_items_in_view));
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.item_data.current_room_location));

    //Inventory Data
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.player_inventory.inv_item));
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.player_inventory.number_of_items_held));
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.player_inventory.occupied));
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.player_inventory.origin_index));
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.player_inventory.tail_index));

    //Room Data
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.view_data.current_view_idx));
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.view_data.npc_in_room));
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.view_data.adjascent_views));
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.view_data.adjascent_views_num));
    for i in VIEW_ENUMS{
        items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.view_data.scenery_items[i].current_description));
    };

    os.close(saveFileHandle);
};

u8RGB_To_u32_RGB888 :: proc (R,G,B:u8) -> u32 {return (cast(u32)R << 16) | (cast(u32)G << 8) | cast(u32)B}

RedOf :: proc (hexRGB888:u32) -> u8 {return u8(hexRGB888 >> 16) & 255}
GreenOf :: proc (hexRGB888:u32) -> u8 {return u8(hexRGB888 >> 8) & 255}
BlueOf :: proc (hexRGB888:u32) -> u8 {return u8(hexRGB888 & 255)}

replace_all_palettes :: proc (using ge:^GlobalEverything, new_room_pal_index:VIEW_ENUMS){
    replace_palette :: proc (target:^sdl2.Surface, current_palette:^[4]u32, new_palette:^[4]u32){
        // uint32_t* pixel_ptr = (uint32_t*)target.pixels;
        pixel_ptr := cast(^u32)target.pixels
        for i in 0..< target.h * target.w {
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
            pixel_ptr = mem.ptr_offset(pixel_ptr, 1)
        };
    };

    for pal_index in VIEW_ENUMS {
        for char_sprite in &surfs.font_surface_array {
            if char_sprite != nil do replace_palette(char_sprite, room_palettes[pal_index], room_palettes[new_room_pal_index]);
        };
        for q in &surfs.quill_array {
            replace_palette(q, room_palettes[pal_index], room_palettes[new_room_pal_index]);
        };
        for npc, i in surfs.npc_portraits {
            replace_palette(surfs.npc_portraits[i], room_palettes[pal_index], room_palettes[new_room_pal_index]);
            replace_palette(surfs.npc_standing[i], room_palettes[pal_index], room_palettes[new_room_pal_index]);
        };
    };
};

handle_default_mode_event :: proc (event:^sdl2.Event, using ge:^GlobalEverything, t:^InputTextBuffer, ){
    #partial switch event.type {
        case .TEXTINPUT:
            if t.elems_in_charBuffer == len(t.charBuffer) - 1 do return;
            char_to_parse := event.text.text[0];
            if char_to_index(char_to_parse) == -1 do return
            char_to_put := char_to_parse;
            t.charBuffer[t.elems_in_charBuffer] = char_to_put; 
            t.elems_in_charBuffer += 1;
            // fmt.printf("Chars in buffer:[%s] Length %i\n", t.charBuffer, t.elems_in_charBuffer);
        case .KEYDOWN: #partial switch event.key.keysym.sym {
            case .BACKSPACE:
                if t.elems_in_charBuffer == 0 do return;
                t.charBuffer[t.elems_in_charBuffer - 1] = 0
                t.elems_in_charBuffer -= 1;
                // fmt.printf("Chars in buffer:[%s] Length %i\n", t.charBuffer, t.elems_in_charBuffer);
            case .RETURN:
                for char in &t.charBuffer {
                    switch char {case 'a'..='z': char -= 32} //make uppercase
                }
                t.tokenBuffer = strings.split(string(t.charBuffer[0:t.elems_in_charBuffer]), " ")
                // fmt.printf("Tokens in buffer: ")
                for token in t.tokenBuffer {fmt.printf("%s ,", token)}
                // fmt.printf("\n")
            }
    }
};

addTxtAnim :: proc (arr:^Text_RenderState, anim: proc (int, ^GlobalSurfaces, string) -> int, blit_data:Maybe(string)){
    arr.current_txt_anim = anim;
    arr.duration_count = 240;
    if blit_data != nil do arr.string_to_blit = blit_data.(string)
};

blit_text :: proc (using gs:^GlobalSurfaces, string_to_blit:string, YPosition:i32, XPosition:i32){
    space_rect:sdl2.Rect ={
        h = font_rect.h,
        w = font_rect.w,
        y = YPosition,
    }

    for i in 0..<len(string_to_blit){
        space_rect.x = i32(i) * 9 + XPosition;
        char_to_blit_idx := char_to_index(string_to_blit[i])
        if char_to_blit_idx == -1 do continue
        sdl2.BlitSurface(font_surface_array[char_to_blit_idx], nil, working_surface, &space_rect);
    };
};


save_animation :: proc (duration:int, gs:^GlobalSurfaces, _:string) -> int{
    blit_text(gs, "+GAME SAVED+", 0, (gs.font_rect.w * 13) );//NOTE: Needed for the screen position
    return duration == 0 ? -1 : duration - 1
};

handle_menu_mode_event :: proc (event:^sdl2.Event, 
    using ge:^GlobalEverything,  
    window:^sdl2.Window, 
    render_surface:^^sdl2.Surface, //Easiest way to do it
    ){
    using ge.render_states.menu;
    if event.type != .KEYDOWN do return;
    #partial switch event.key.keysym.sym {
        case .UP:
            if selected_option_index != 0 do selected_option_index -= 1;
        case .DOWN:
            if selected_option_index != 2 do selected_option_index += 1;
        case .LEFT:
            if res_option_index != 0 do res_option_index -= 1;
        case .RIGHT:
            if res_option_index != 4 do res_option_index += 1;
        case .RETURN: switch selected_option_index {
            case 0:
                if prev_res_option_index == res_option_index do return;
                prev_res_option_index = res_option_index;
                sdl2.SetWindowSize(window, i32(NATIVE_WIDTH * (res_option_index + 1)), i32(NATIVE_HEIGHT * (res_option_index + 1)));
                render_surface^ = sdl2.GetWindowSurface(window);
            case 1:
                save_data.res_index = res_option_index;
                handle_savegame_io(.WRITE, &save_data);
                addTxtAnim(&ge.render_states.txt, save_animation,  nil);
                game_mode = ._Default;
            case 2:
                res_option_index = prev_res_option_index;
                game_mode = ._Default;
            }
    }
};

handle_dialogue_mode_event :: proc ( event:^sdl2.Event, using ge:^GlobalEverything){
    using ge.render_states.npc
    if event.type != .KEYDOWN do return;
    #partial switch event.key.keysym.sym {
        case .RETURN:
            if len(current_node.child_nodes) == 0 {
                game_mode = ._Default;
                return;
            };
            current_node = current_node.child_nodes[selected_dialogue_option];
            number_of_options = len(current_node.child_nodes);
            selected_dialogue_option = 0;
        case .UP:
            if current_node.child_nodes[1] == nil do break
            if selected_dialogue_option != 0 do selected_dialogue_option -= 1;
        case .DOWN:
            if current_node.child_nodes[1] == nil do break
            if selected_dialogue_option != (number_of_options - 1) do selected_dialogue_option += 1;
    }
};

handle_inventory_mode_event :: proc (event:^sdl2.Event, using ge:^GlobalEverything){
    using ge.render_states.inv
    if event.type != .KEYDOWN do return;
    exit_option_selected := row_selected == (MAX_ITEMS_IN_INVENTORY / 2)
    #partial switch event.key.keysym.sym {
        case .UP:
            if row_selected != 0 do row_selected -=1
        case .DOWN:
            if exit_option_selected do return
            row_selected += 1;
            if row_selected == (MAX_ITEMS_IN_INVENTORY / 2) do left_column_selected = true;
        case .LEFT:
            left_column_selected = true;
        case .RIGHT:
            if !exit_option_selected do left_column_selected = false;
        case .RETURN:
            if exit_option_selected do game_mode = ._Default;
    }
};

blit_tile :: proc (space:^sdl2.Surface, blit_length:int, working_surface:^sdl2.Surface, YPosition:i32, XPosition:i32){
    space_rect:sdl2.Rect;
    space_rect.h = space.clip_rect.h; space_rect.w = space.clip_rect.w;
    space_rect.y = YPosition;
    for i in 0..<blit_length{
        space_rect.x = i32(i) * 8 + XPosition;
        sdl2.BlitSurface(space, nil, working_surface, &space_rect);
    };
};


LookModifier :: enum {
    _DefaultLook ,
    _LookInside,
};

parse_look_modifier :: proc ( str:string) -> LookModifier {
    switch str {
        case "IN", "WITHIN", "INSIDE": return ._LookInside;
    }
    return ._DefaultLook;
}

inventory_add_item :: proc (inv:^PlayerInventory, new_item:PLAYER_ITEM) -> i8 {
    new_inv_item:InventoryItem_ListElem;
    new_inv_item.item_enum = new_item;
    new_inv_item.next_item_index = -1;

    if inv.tail_index == -1 {
        inv.inv_item[0] = new_inv_item;
        inv.occupied[0] = true;
        inv.tail_index = 0;
        inv.origin_index = 0;
        inv.number_of_items_held +=1 ;
        return 0;
    };
    for i in 0..< MAX_ITEMS_IN_INVENTORY {
        if inv.occupied[i] == true do continue;
        if inv.tail_index != -1 do inv.inv_item[inv.tail_index].next_item_index = cast(i8)i;
        inv.tail_index = cast(i8)i;
        inv.occupied[i] = true;
        inv.inv_item[i] = new_inv_item;
        inv.number_of_items_held +=1;
        return cast(i8)i;
    };
    //All slots occupado
    return -1;
};

inventory_delete_item :: proc ( inv:^PlayerInventory, deletion_index:i8) -> int {
    if deletion_index == inv.origin_index {
        //TODO: ruh roh, whats going on here
        new_origin_index := inv.inv_item[inv.origin_index].next_item_index;
        mem.zero(&inv.inv_item[inv.origin_index], 1)
        inv.occupied[inv.origin_index] = false;
        inv.number_of_items_held -= 1;
        return 0;
    };
    for i in 0..<MAX_ITEMS_IN_INVENTORY {
        if(inv.inv_item[i].next_item_index != deletion_index){continue;};
        inv.inv_item[i].next_item_index = inv.inv_item[deletion_index].next_item_index;
        inv.tail_index = cast(i8)i;
        mem.zero(&inv.inv_item[deletion_index], 1)
        inv.occupied[deletion_index] = false;
        inv.number_of_items_held -= 1;
        return 0;
    };
    //All slots occupado
    return -1;
};

import "core:runtime"

blit_general_string ::  proc (duration:int, using payload:^GlobalSurfaces, str:string) -> int {
    new_strings:= make([dynamic]string, 0, 8, context.temp_allocator)
    text  := str
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

    for string, idx in new_strings {
        YPosition: = (NATIVE_HEIGHT) - (font_rect.h * i32(len(new_strings) - idx ));
        blit_tile(font_surface_array[char_to_index(u8(' '))],LENGTH_OF_CHAR_BUFFER_ARRAY + 4, working_surface, YPosition, 0); 
        blit_text(payload, string, YPosition, 0);   
    }
    
    return duration == 0 ? -1 : duration - 1;            
} 


handle_command :: proc (
    command:ValidCommand, 
    ge:^GlobalEverything,
    text_buffer:^InputTextBuffer, 
    ){
    using ge;
    using text_buffer

    str:Maybe(string) = nil
    defer if str != nil do addTxtAnim(&render_states.txt, blit_general_string, str);

    switch(command){
        case .Save: 
            handle_savedata(&save_data, ge, .WRITE)
            handle_savegame_io(.WRITE, &save_data);
            addTxtAnim(&render_states.txt, save_animation,  nil);
        case .Menu: game_mode = ._Menu; 
        case .Quit: sdl2.PushEvent(&sdl2.Event{type = .QUIT});
        case .Go: using view_data;
            if len(tokenBuffer) == 1 {str = "Where would you like to go?";break;};
            new_index, ok := reflect.enum_from_name(VIEW_ENUMS, tokenBuffer[1]);
            switch {
                case ok && new_index == current_view_idx: str = "You're already here!"
                case !ok || new_index not_in adjascent_views[current_view_idx]: str = fmt.aprintf( "'%s' isn't near here.", tokenBuffer[1])
                case view_type[new_index] != .Room: str = "You cannot fit in there!"
                case ok:
                    render_states.txt.duration_count = 0; view_data.current_view_idx = new_index;
                    replace_all_palettes(ge, new_index);
            }
        case .Look: using view_data;
            if len(tokenBuffer) == 1 {str = "What would you like to look at?";break;};
            switch(parse_look_modifier(tokenBuffer[1])){
                case ._LookInside: 
                    if(len(tokenBuffer) == 2){str = "What would you like to look in?"; break;};
                    new_index, ok := reflect.enum_from_name(VIEW_ENUMS, tokenBuffer[2]);
                    switch {
                        case tokenBuffer[2] == "INVENTORY": 
                            game_mode = ._Inventory;
                        case ok && view_type[new_index] == .LookInside:  
                            render_states.txt.duration_count = 0; current_view_idx = new_index;
                        case: 
                            str = "Cannot look inside there.";
                    }
                case ._DefaultLook: 
                    item_index, item_ok := item_name_to_index(tokenBuffer[1], &item_state.player_items);
                    scenery_item_index, scenery_ok := scenery_item_name_to_index(tokenBuffer[1], &scenery_items[current_view_idx]);
                    npc_index, npc_ok := reflect.enum_from_name(NPC_ENUM, tokenBuffer[1])
                    switch {
                        case tokenBuffer[1] == "INVENTORY": 
                            game_mode = ._Inventory
                        case item_ok: using item_state.player_items;
                            desc_idx := current_description[item_index]
                            str = current_room_location[item_index] == current_view_idx ? item_descriptions[item_index][desc_idx]: fmt.aprintf("Cannot find the '%s'.", tokenBuffer[1])
                        case scenery_ok: 
                            desc_idx := scenery_items[current_view_idx].current_description[scenery_item_index]
                            str = scenery_items[current_view_idx].item_descriptions[scenery_item_index][desc_idx]
                        case npc_ok: 
                            str = npc_in_room[current_view_idx] == npc_index ? npc_description[npc_index] : fmt.aprintf("Cannot find the '%s'.", tokenBuffer[1])
                    }
                }
        case .Take: using item_state;
            if len(tokenBuffer) == 1 {str = "What would you like to take?";break;};
            item_index, ok := item_name_to_index(tokenBuffer[1], &player_items);
            switch {
                case !ok || player_items.current_room_location[item_index] != view_data.current_view_idx:
                    str = fmt.aprintf( "Cannot find the '%s'.", tokenBuffer[1])
                case:
                    player_items.is_item_taken += {item_index}
                    player_items.current_room_location[item_index] = nil;
                    player_items.number_of_items_in_view[view_data.current_view_idx] -=1;
                    player_items.index_within_inventory[item_index] = inventory_add_item(&player_inv, item_index); // likely to be taken out
        
                    if(view_data.events[view_data.current_view_idx].take_events[item_index] != nil){ //Do the event
                        view_data.events[view_data.current_view_idx].take_events[item_index](&player_items, &view_data.scenery_items[view_data.current_view_idx]);
                    };
                    str = fmt.aprintf( "You take the '%s'.", tokenBuffer[1]);
            }
        case .Place: using view_data
            if len(tokenBuffer) == 1 {str = "What would you like to place?";break;};
            item_enum, ok := item_name_to_index(tokenBuffer[1], &item_state.player_items);
            index_within_inventory := item_state.player_items.index_within_inventory[item_enum];
            switch {
                case !ok || index_within_inventory == -1:
                    str = fmt.aprintf( "You have no '%s'.", tokenBuffer[1])
                case len(tokenBuffer) == 2:
                    str = "Where would you like to place it?"
            }
            destination_index, dest_ok := scenery_item_name_to_index(tokenBuffer[2], &scenery_items[current_view_idx]);
            switch {
                case !dest_ok: 
                    str = fmt.aprintf( "Cannot find the '%s'.", tokenBuffer[2]);
                case events[current_view_idx].place_events[item_enum].scenery_dest_index != destination_index:
                    str = "You can't place that there."
                case: 
                    if(events[current_view_idx].place_events[item_enum].event != nil){
                        events[current_view_idx].place_events[item_enum].event(&item_state.player_items, &scenery_items[current_view_idx]);
                    }
                    item_state.player_items.is_item_taken -= {item_enum} 
                    item_state.player_items.current_room_location[item_enum] = current_view_idx;
                    item_state.player_items.number_of_items_in_view[current_view_idx] += 1;
                    item_state.player_items.index_within_inventory[item_enum] = -1;
                    inventory_delete_item(&item_state.player_inv, index_within_inventory);
                    str = fmt.aprintf( "The '%s' is placed.", tokenBuffer[1])
            }
        case .Talk:
            if len(tokenBuffer) == 1 {str = "Who would you like to talk to?";break;};
            npc_index, ok := reflect.enum_from_name(NPC_ENUM, tokenBuffer[1])
            switch {
                case !ok || view_data.npc_in_room[view_data.current_view_idx] != npc_index:
                    str = fmt.aprintf("'%s' is not here.", tokenBuffer[1]);
                case:
                    render_states.npc.current_npc = npc_index;
                    render_states.npc.current_node = dialogue_data.starter_nodes[npc_index];
                    game_mode = ._Dialogue;
            }
        case .Inventory: game_mode = ._Inventory;
        case .ListExits: using view_data
            context.allocator = context.temp_allocator
            viewnames:[dynamic]string
            for view in VIEW_ENUMS {
                if view_type[view] == .LookInside do continue
                if view in adjascent_views[current_view_idx] do append(&viewnames, reflect.enum_string(view))
            }
            gronk := strings.join(viewnames[:], ", ")
            str = strings.concatenate({"Current exits:\n", gronk})
        case .Invalid, .Exit:{};
    }
};

init_player_item_data :: proc (s:^Item_State, view_data:^ViewData){

    for i in 0..<MAX_ITEMS_IN_INVENTORY {
        s.player_inv.inv_item[i] = {nil, -1};
        s.player_inv.occupied[i] = false;
    };
    s.player_inv.origin_index = -1;
    s.player_inv.tail_index = -1;
    s.player_inv.number_of_items_held = 0;


    for i in PLAYER_ITEM {
        s.player_items.current_room_location[i] = nil;
        s.player_items.index_within_inventory[i] = -1;
        s.player_items.is_item_taken -= {i}
    };

    add_item_to_PlayerItemData :: proc (using player_items:^PlayerItemData, 
        idx:PLAYER_ITEM, 
        default_description:string,
        is_takeable:bool,
        room_enum:VIEW_ENUMS,
        ){
        @static  current_number_of_items := 0;
        assert(current_number_of_items < MAX_INVENTORY_ITEMS);
        item_descriptions[idx] = make([dynamic]string)
        append(&item_descriptions[idx], default_description)
        if is_takeable do is_takeable_item += {idx}
        current_room_location[idx] = room_enum;
        number_of_items_in_view[room_enum] += 1
        index_within_inventory[idx] -= 1;
        current_number_of_items += 1;
    };

    add_scenery_item :: proc (using scenery_items:^SceneryItemData, name:string, description:string){
        assert(number_of_items <= 16)
        idx := number_of_items;
        item_name[idx] = name
        item_descriptions[idx] = make([dynamic]string)
        append(&item_descriptions[idx], description)
        number_of_items += 1;
    }
    add_scenery_item_description :: proc (using scenery_items:^SceneryItemData, name:string, description:string) {
        idx, _ := scenery_item_name_to_index(name, scenery_items)
        current_num_of_descs:= len(scenery_items.item_descriptions[idx])
        append(&item_descriptions[idx], description)
    }

    add_player_item_description :: proc (using player_items:^PlayerItemData, idx:PLAYER_ITEM, description:string){
        append(&item_descriptions[idx], description)
    }

    add_item_to_PlayerItemData(&s.player_items, .AXE, "The axe is stumpwise lodged.", true, .CLEARING);
    add_player_item_description(&s.player_items, .AXE, "It's a well balanced axe. Much use.")
    s.player_items.synonyms[.AXE][0] = "HATCHET"

    take_axe_event :: proc (player_items:^PlayerItemData, scenery_items:^SceneryItemData){
        stump_index, ok := scenery_item_name_to_index("STUMP", scenery_items);
        scenery_items.current_description[stump_index] = 1
        player_items.current_description[.AXE] = 1
    };
    view_data.events[.CLEARING].take_events[.AXE] = take_axe_event;
    axe_in_stump_event:PlaceEvent 
    axe_in_stump_event.scenery_dest_index, _ = scenery_item_name_to_index("STUMP", &view_data.scenery_items[.CLEARING]);
    
    place_axe_in_stump_event :: proc ( player_items:^PlayerItemData,  scenery_items:^SceneryItemData){
        stump_index, _ := scenery_item_name_to_index("STUMP", scenery_items);
        scenery_items.current_description[stump_index] = 0
        player_items.current_description[.AXE] = 0
    };
    
    axe_in_stump_event.event = place_axe_in_stump_event;
    view_data.events[.CLEARING].place_events[.AXE] = axe_in_stump_event;

    lazarus_icon_description :="An icon St Lazarus being raised from the dead by Christ."
    add_item_to_PlayerItemData(&s.player_items, .LAZARUS_ICON, lazarus_icon_description, true, .SHRINE);
    s.player_items.synonyms[.LAZARUS_ICON][0] = "ICON";
    s.player_items.synonyms[.LAZARUS_ICON][1] = "LAZARUS";

    icon_in_shrine_event:PlaceEvent;
    icon_in_shrine_event.scenery_dest_index, _ = scenery_item_name_to_index("SHRINE", &view_data.scenery_items[.SHRINE]);
    view_data.events[.SHRINE].place_events[.LAZARUS_ICON] = icon_in_shrine_event;
}



main :: proc (){
	using sdl2;
    if Init( INIT_VIDEO ) < 0 {
        fmt.printf( "SDL could not initialize! SDL_Error: %s\n", sdl2.GetError() );
        return;
    } 
    FPS :: 60;
    frameDuration :: 1000 / FPS;
    ge:GlobalEverything;
	init_everything(&ge)
    alexei_start:DialogueNode = {
        dialogue_text = "Your time is nigh.\n...Repent!",
    };
    alexei_second:DialogueNode = {
        dialogue_text = "...Else into the hole with you!", 
        parent_node = &alexei_start,
    };
    alexei_third_1:DialogueNode = {
        selection_option = "Hole?", 
        dialogue_text = "Yes, hole.\nThe deep hole has many sharp bits. It will be hard to fish you out.",
        parent_node = &alexei_second,
    };
    alexei_third_2:DialogueNode = {
        selection_option = "I'm not repenting.", 
        dialogue_text = "Alexei shakes his head. You're already in deep.",
        parent_node = &alexei_second,
    };
    alexei_dialogue:[4]^DialogueNode = {&alexei_start, &alexei_second, &alexei_third_1, &alexei_third_2};

    init_dialogue_nodes :: proc (nodes:[]^DialogueNode){
        for node in nodes {
            node.child_nodes = make_dynamic_array([dynamic]^DialogueNode)
            if node.parent_node == nil do continue;
            child_node_index := len(node.parent_node.child_nodes);
            append(&node.parent_node.child_nodes, node)
        };
    };
    init_dialogue_nodes(alexei_dialogue[:])
    ge.dialogue_data.starter_nodes[.ALEXEI] = alexei_dialogue[0]
    text_buffer:InputTextBuffer;
    //NOTE: Fix text


	using ge;

    saveFileHandle, err := os.open("save.dat", os.O_RDONLY)
    fresh_game := err == os.ERROR_FILE_NOT_FOUND;
    os.close(saveFileHandle)
    if (fresh_game){
        createFileHandle, err := os.open("save.dat", os.O_CREATE)
        //Init default save data
        handle_savedata(&save_data, &ge, .WRITE)
     os.close(createFileHandle)
    }
    handle_savegame_io(fresh_game ? .WRITE : .READ, &save_data);

    if (!fresh_game){
        //Read save data
        handle_savedata(&save_data, &ge, .READ)
    };

    replace_all_palettes(&ge, save_data.view_data.current_view_idx);

    ge.settings.window_size = save_data.res_index + 1
    window := sdl2.CreateWindow("Searching for the Name", 
       	sdl2.WINDOWPOS_UNDEFINED,	sdl2.WINDOWPOS_UNDEFINED, 
        i32(NATIVE_WIDTH * ge.settings.window_size), 
        i32(NATIVE_HEIGHT * ge.settings.window_size), 
        sdl2.WINDOW_SHOWN );
    if window == nil {
        fmt.printf( "Window could not be created! SDL_Error: %s\n", sdl2.GetError());
        return ;
    };

    render_surface := sdl2.GetWindowSurface( window );
    surfs.working_surface = sdl2.CreateRGBSurface(0, 
        NATIVE_WIDTH, NATIVE_HEIGHT, 
        i32(render_surface.format.BitsPerPixel), u32(render_surface.format.Rmask), 
        render_surface.format.Gmask, render_surface.format.Bmask, render_surface.format.Amask);
    //^^^ setup window, render_surface, and working_surface handles here ^^^

    for settings.quit != true {
		sdl2.StartTextInput()
        frameStart := sdl2.GetTicks();
        event:sdl2.Event;
        for( sdl2.PollEvent( &event ) != false ){
            if (event.type == .QUIT){settings.quit = true;break;};
            switch(game_mode){
                case ._Default, ._LookInside: handle_default_mode_event(&event, &ge, &text_buffer);
                case ._Menu: handle_menu_mode_event(&event, &ge, window, &render_surface);
                case ._Dialogue: handle_dialogue_mode_event(&event, &ge);
                case ._Inventory: handle_inventory_mode_event(&event, &ge);
            };
        };
        
        if len(text_buffer.tokenBuffer) > 0 {
            command: = parse_token(text_buffer.tokenBuffer[0]);
            handle_command(command, &ge, &text_buffer);
        }
        defer if len(text_buffer.tokenBuffer) > 0 do mem.zero_item(&text_buffer)
        //blit background
        sdl2.BlitSurface(surfs.view_background_surfaces[view_data.current_view_idx], nil, surfs.working_surface, nil); 
        for i in PLAYER_ITEM { //blit items
            using item_state.player_items, view_data, surfs
            if i in is_item_taken do continue;
            item_sprite := item_in_view_surfaces[i][current_view_idx];
            if item_sprite != nil do sdl2.BlitSurface(item_sprite, nil, working_surface, &item_sprite.clip_rect);
        };

        switch(game_mode){
            case ._Inventory: render_inventory(&ge)
            case ._Menu: render_menu(&ge)
            case ._Dialogue: render_dialogue(&ge)
            case ._Default, ._LookInside: render_default(&ge, &text_buffer)
        }

        sdl2.BlitScaled(surfs.working_surface, nil, render_surface, nil);
        sdl2.UpdateWindowSurface(window);

        frameTime := sdl2.GetTicks() - frameStart;
        if frameDuration > frameTime do sdl2.Delay(frameDuration - frameTime);
    };
    sdl2.Quit();
    return ;
}
