package init;

import "core:intrinsics"
import "core:fmt"
import "core:reflect"
import "core:strings"
import "core:slice"
import "vendor:sdl2"

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

add_scenery_item :: proc(using data:^SceneryItemData, view:VIEW_ENUM, name:string, _descriptions:..string){
    append(&sceneryItemNames[view], name)
    append(&enum_state[view], 0)
    append(&descriptions[view], slice.clone(_descriptions[:]))
}

init_scenery_items :: proc (using view_data:^ViewData){
    for view in VIEW_ENUM {
		scenery_items.sceneryItemNames[view] = make([dynamic]string)
		scenery_items.enum_state[view] = make([dynamic]int)
		scenery_items.descriptions[view] = make([dynamic][]string)
	}
    add_scenery_items_hot(&view_data.scenery_items)

    for view in VIEW_ENUM {
        shrink(&scenery_items.descriptions[view])
        shrink(&scenery_items.enum_state[view])
        shrink(&scenery_items.sceneryItemNames[view])
    }
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

add_synonym :: proc(data:^Synonyms, synonym:string, synonym_for:..union{PLAYER_ITEM,Synonym_SceneryItem}){
    pItem_dynArray:[dynamic]PLAYER_ITEM; 
    for x in synonym_for {
        #partial switch v in x {
            case PLAYER_ITEM: append(&pItem_dynArray, v);
        }
    }
    shrink(&pItem_dynArray)

    sItem_dynArray: [dynamic]Synonym_SceneryItem;
    for x in synonym_for {
        #partial switch v in x {
            case Synonym_SceneryItem: append(&sItem_dynArray, v);
        }
    }
    shrink(&sItem_dynArray)

    append(&data.synonym, synonym)
    append(&data.player_item, pItem_dynArray[:])
    append(&data.scenery_item, sItem_dynArray[:])
}

scenery_item_name_to_index :: proc (name:string, ge:^GlobalEverything, view_idx:VIEW_ENUM) -> (idx:int, ok:bool){
    using ge.view_data
    for str, idx in scenery_items.sceneryItemNames[view_idx] {
        if name == str do return idx, true
    };
    fmt.printf("Failed get on %s \n", name)
    return -1, false
};

init_save_data_struct :: proc (save_data:^SaveData, ge:^GlobalEverything) {
    for savedata_arr, e_idx in &save_data.view_data.scenery_items.enum_state {
        savedata_arr = make([dynamic]int, len(ge.view_data.scenery_items.enum_state[e_idx]), cap(ge.view_data.scenery_items.enum_state[e_idx]))
    }
}

add_playerItem :: proc(data:^PlayerItemData, in_view:Maybe(VIEW_ENUM), item:PLAYER_ITEM, description:..string){
    data.enum_state[item] = 0 ;
    data.view_location[item] = in_view;
    data.descriptions[item] = slice.clone(description[:])
}

init_player_item_data_cold :: proc (s:^Item_State, view_data:^ViewData, ge:^GlobalEverything){

    for i in 0..<MAX_ITEMS_IN_INVENTORY {
        s.player_inv.inv_item[i] = {nil, -1};
        s.player_inv.occupied[i] = false;
    };
    s.player_inv.origin_index = -1;
    s.player_inv.tail_index = -1;
    s.player_inv.number_of_items_held = 0;


    for i in PLAYER_ITEM {
        s.player_items.view_location[i] = nil;
        s.player_items.index_in_inventory[i] = -1;
    };
    init_player_item_data_hot(s)
    add_synonyms_hot(ge)

    take_axe_event :: proc (ge:^GlobalEverything){
        stump_index, ok := scenery_item_name_to_index("STUMP", ge, ge.view_data.current_view_idx);
        using ge.view_data
        scenery_items.enum_state[current_view_idx][stump_index] = cast(int)vSTUMP_ItemState.Default
    };
    view_data.events[.CLEARING].take_events[.AXE] = take_axe_event;
    axe_in_stump_event:PlaceEvent 
    axe_in_stump_event.scenery_dest_index, _ = scenery_item_name_to_index("STUMP", ge, .CLEARING);
    
    place_axe_in_stump_event :: proc (ge:^GlobalEverything){
        stump_index, _ := scenery_item_name_to_index("STUMP", ge,  ge.view_data.current_view_idx);
        using ge.view_data
        scenery_items.enum_state[current_view_idx][stump_index] = cast(int)vSTUMP_ItemState.AxewiseStuck
    };
    
    axe_in_stump_event.event = place_axe_in_stump_event;
    view_data.events[.CLEARING].place_events[.AXE] = axe_in_stump_event;

    place_icon_in_shrine_event :: proc (ge:^GlobalEverything){
        stump_index, _ := scenery_item_name_to_index("SHRINE", ge,  ge.view_data.current_view_idx);
        using ge.view_data
        scenery_items.enum_state[current_view_idx][stump_index] = cast(int)vSTUMP_ItemState.AxewiseStuck
    };

    icon_in_shrine_event:PlaceEvent;
    icon_in_shrine_event.scenery_dest_index, _ = scenery_item_name_to_index("SHRINE", ge, .CHURCH);
    view_data.events[.SHRINE].place_events[.LAZARUS_ICON] = icon_in_shrine_event;
}

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

    view_data.adjascent_views[.SHRINE] = {.CHURCH}
    view_data.adjascent_views[.CHURCH] = {.CLEARING, .SHRINE}
    view_data.adjascent_views[.CLEARING] = {.CHURCH, .SKETE}
    view_data.adjascent_views[.SKETE] = {.CLEARING, .CHAPEL}
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
    init_synonyms :: proc(data:^Synonyms) {
        data.synonym = make([dynamic]string)
        data.scenery_item = make([dynamic][]Synonym_SceneryItem)
    }

    init_synonyms(&ge.synonyms)
    init_scenery_items(&view_data);
    init_npc_descriptions_hot(&view_data);
    init_surfaces(&surfs)

    // Done
	game_mode = ._Default

    init_player_item_data_cold(&item_state, &ge.view_data, ge);
    render_states.inv.left_column_selected = true
}