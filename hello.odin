package main

import "core:fmt";
import "core:strings";
import "core:slice";
import "core:os";
import "vendor:sdl2";


NATIVE_WIDTH :: 320
NATIVE_HEIGHT :: 200

NUMBER_OF_VIEWS :: 4
NUMBER_OF_NPCS :: 1
LENGTH_OF_CHAR_BUFFER_ARRAY :: 36
LENGTH_OF_QUILL_ARRAY :: 4
LENGTH_OF_FONT_SURFACE_ARRAY :: 96
NUMBER_OF_PLAYER_ITEMS :: 16

MAX_NUMBER_OF_SCENERY_ITEMS :: 16
MAX_NUMBER_OF_SYNONYMS :: 8

Foo :: enum {
    _bar,
    _baz,
}

return_int :: proc (_foo:Foo) -> int {
    return _foo == ._bar ? 0 : 4
}

// package main

// import "core:fmt"
// import "core:reflect"

// My_Enum :: enum {
//     Foozle,
//     Barzle,
//     Boop,
//     Hellope,
// }

// My_Enum_Names :: [My_Enum]string{
//     .Foozle  = "Foozle?",
//     .Barzle  = "Barzle!",
//     .Boop    = "Boop?!",
//     .Hellope = "Hellope!",
// }

// name_from_value :: reflect.enum_string
// value_from_name :: reflect.enum_from_name



// main :: proc() {
//     using fmt
//     e := My_Enum.Foozle
//     names := My_Enum_Names
//     printf("reflect.enum_string(e): %v\n", name_from_value(e))
//     printf("enumerated array: %v\n", names[e])
//     val, ok := value_from_name(My_Enum, "Barzle")
//     printf("reflect.enum_from_name(My_Enum, \"Barzle\"): %v (ok: %v)\n", val, ok)
// }


//------------------------

// import "core:fmt"
// import "core:reflect"

// My_Enum :: enum {
//     Foozle,
//     Barzle,
//     Boop,
//     Hellope,
// }

// name_from_value :: reflect.enum_string
// value_from_name :: reflect.enum_from_name

// main :: proc() {
//     using fmt
//     e := My_Enum.Foozle
//     printf("reflect.enum_string(e): %v\n", name_from_value(e))
//     val, ok := value_from_name(My_Enum, "Barzle")
//     printf("reflect.enum_from_name(My_Enum, \"Barzle\"): %v (ok: %v)\n", val, ok)
// }

// reflect.enum_string(e): Foozle
// reflect.enum_from_name(My_Enum, "Barzle"): Barzle (ok: true)

Point_i32 :: struct {
    x:i32,
    y:i32,
}

 GlobalSurfaces :: struct {
    working_surface:^sdl2.Surface ,
    font_surface_array:[LENGTH_OF_FONT_SURFACE_ARRAY]^sdl2.Surface,
    view_background_surfaces:[VIEW_ENUMS]^sdl2.Surface,
    quill_array:[LENGTH_OF_QUILL_ARRAY]^sdl2.Surface,
    // Better solution needed, to get rid of dead data? Irrelevant for now?
    item_in_view_surfaces:[ITEM_ENUMS][VIEW_ENUMS]^sdl2.Surface,
    item_points_in_view:[ITEM_ENUMS][VIEW_ENUMS]Point_i32,
    npc_portraits:[NPC_ENUM]^sdl2.Surface,
    npc_standing:[NPC_ENUM]^sdl2.Surface,
    font_rect: sdl2.Rect,
};

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

GameSettings :: struct {
    window_size:int, // default = 1
    quit:bool, // default = false
};

SceneryItemData :: struct {
    item_name:[MAX_NUMBER_OF_SCENERY_ITEMS]string,
    item_description:[MAX_NUMBER_OF_SCENERY_ITEMS]string,
    synonyms:[MAX_NUMBER_OF_SCENERY_ITEMS][MAX_NUMBER_OF_SYNONYMS]string,
    number_of_items:int,
};

ViewData :: struct {
    current_view_idx: VIEW_ENUMS, 
    npc_in_room:[VIEW_ENUMS]Maybe(NPC_ENUM),
    npc_description:[NPC_ENUM][5]string,
    scenery_items:[VIEW_ENUMS]SceneryItemData,
    events:[VIEW_ENUMS]EventData,
    view_type:[VIEW_ENUMS]ViewType,
    adjascent_views:[VIEW_ENUMS][VIEW_ENUMS]bool, // adjascent_views[view_to_query][is_this_adjascent]
    adjascent_views_num:[VIEW_ENUMS]int, // This and the above could be refactored as dynamic array
};

GlobalEverything :: struct {
    settings:GameSettings,
    surfs:GlobalSurfaces,
    view_data:ViewData,
    game_mode:GameMode,
};

MAX_STRING_SIZE :: 36

Text_RenderState :: struct {
    current_txt_anim: proc (int, ^GlobalSurfaces, string) -> int,
    duration_count:int,
    temp_data:string, // Is this needed with future allocator stuff?
};

Inventory_RenderState :: struct{
    quit_string:string,// "  EXIT INVENTORY", quit_string:[16]u8 = "  EXIT INVENTORY"
    left_column_selected: bool,
    row_selected:int,
};

Menu_RenderState :: struct {
    res_option_str:[5]string , //{"1\0", "2\0", "3\0", "4\0", "5\0"};
    option_string:[3]string, // = {"  WINDOW SCALE X", "  SAVE", "  QUIT"};
    res_option_index,  prev_res_option_index, selected_option_index :int,
};

DialogueNode :: struct {
    selection_option:string,// 
    dialogue_text:string,
    parent_node:^DialogueNode,
    child_nodes:[5]^DialogueNode,
    number_of_child_nodes:int,
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

init_scenery_items :: proc (view_data:^ViewData){
    add_scenery_item :: proc (scenery_items:^SceneryItemData, item_name:string, item_description:string ){
        assert(scenery_items.number_of_items <= 16)
        i := scenery_items.number_of_items;
        scenery_items.item_name[i] = item_name
        scenery_items.item_description[i] = item_description
        scenery_items.number_of_items += 1;
    }
    //TODO: After string refactor, just put feed the arg in as a string lit
    church_self_description := "Dedicated to Saint Lazarus, this modest Church stands strong."
    add_scenery_item(&view_data.scenery_items[.CHURCH], "CHURCH", church_self_description);
    shrine_description := "The shrine stands tall on the hill, proud of its older brother."
    add_scenery_item(&view_data.scenery_items[.CHURCH], "SHRINE", shrine_description);
    church_tree_description := "It is a bare tree, standing alone."
    add_scenery_item(&view_data.scenery_items[.CHURCH], "TREE", "It is a bare tree, standing alone.");
    church_gate_description := "Crudely drawn, and unfinished."
    add_scenery_item(&view_data.scenery_items[.CHURCH], "GATE", church_gate_description);
    fmt.printf("Number of items in church context %v \n", view_data.scenery_items[.CHURCH].number_of_items)

    clearing_self_description := "A quiet clearing. A good place to find lazy trees."
    add_scenery_item(&view_data.scenery_items[.CLEARING], "CLEARING", clearing_self_description);
    stump_description := "The stump is axewise stuck."
    add_scenery_item(&view_data.scenery_items[.CLEARING], "STUMP", stump_description);
    tree_description := "Loitering in the clearing, the trees don't have much to do." 
    add_scenery_item(&view_data.scenery_items[.CLEARING], "TREES", tree_description);
    fmt.printf("Number of items in CLEARING context %v \n", view_data.scenery_items[.CLEARING].number_of_items)

    shrine_self_description := "Almost like a miniature church, the shrine keeps travellers hopes in a travel-sized temple."
    add_scenery_item(&view_data.scenery_items[.SHRINE], "SHRINE", shrine_self_description);
    candle_description := "A sleeping soldier of metal and oil waits for its next call to duty."
    add_scenery_item(&view_data.scenery_items[.SHRINE], "CANDLE", candle_description);
};

init_npc_descriptions :: proc (vd:^ViewData){  
    alexei_description:[5]string = {
        "Alexei is stern, yet lively. His", "arms yearn to throw fools into ", "deep, dark pits.", "", "",
    };
    vd.npc_description[.ALEXEI] = alexei_description

};

global_buffer: [4*mem.Kilobyte]byte
global_arena: mem.Arena

init_everything :: proc (using ge:^GlobalEverything) {
    mem.init_arena(&global_arena, global_buffer[:])
	context.allocator = mem.arena_allocator(&global_arena)
	settings.quit = false
	settings.window_size = 1

	view_data.current_view_idx = .CHURCH


    //TODO: Turn these into dynamic arrays of enums after port⌈
    view_data.adjascent_views_num[.SHRINE] = 1;
    view_data.adjascent_views[.SHRINE][.CHURCH] = true;

    view_data.adjascent_views_num[.CHURCH] = 2;
    view_data.adjascent_views[.CHURCH][.CLEARING] = true;
    view_data.adjascent_views[.CHURCH][.SHRINE] = true;

    view_data.adjascent_views_num[.CLEARING] = 2;
    view_data.adjascent_views[.CLEARING][.CHURCH] = true;
    view_data.adjascent_views[.CLEARING][.SKETE] = true;

    view_data.adjascent_views_num[.SKETE] = 2;
    view_data.adjascent_views[.SKETE][.CLEARING] = true;
    view_data.adjascent_views[.SKETE][.CHAPEL] = true;

    view_data.adjascent_views_num[.CHAPEL] = 1;
    view_data.adjascent_views[.CHAPEL][.SKETE] = true;

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
    // Done
    context.allocator = context.temp_allocator
    load_views :: proc (array_ref:^[VIEW_ENUMS]^sdl2.Surface) {
        for x, idx in array_ref {
            temp_directory:[32]byte;
            temp_dir := fmt.bprintf(temp_directory[:], "assets/%s.bmp", reflect.enum_string(idx));
            fmt.printf("tempdir -> %s \n", temp_dir)
            array_ref[idx] = sdl2.LoadBMP(strings.clone_to_cstring(temp_dir));
        };
    };
    load_font_files :: proc (array:^[LENGTH_OF_FONT_SURFACE_ARRAY]^sdl2.Surface ){
        temp_directory:[32]byte
        for i in 0..=25 {
            temp_directory:[32]byte;
            temp_dir := fmt.bprintf(temp_directory[:], "assets/font/cap_%c.bmp", 'A' + i);
            array[char_to_index('A' + i)] = sdl2.LoadBMP(strings.clone_to_cstring(temp_dir));
        };
        for i in 0..=25 {
            temp_directory:[32]byte;
            temp_dir := fmt.bprintf(temp_directory[:], "assets/font/low_%c.bmp", 'a' + i);
            array[char_to_index('a' + i)] = sdl2.LoadBMP(strings.clone_to_cstring(temp_dir));
        };
        for i in 0..<10 {
            temp_directory:[32]byte;
            temp_dir := fmt.bprintf(temp_directory[:], "assets/font/%c.bmp", '0' + i);
            fmt.printf("Doing array thing for %i \n", i)
            array[char_to_index('0' + i)] = sdl2.LoadBMP(strings.clone_to_cstring(temp_dir));
        };
        array[char_to_index(cast(u8)' ')] = sdl2.LoadBMP(strings.clone_to_cstring("assets/font/space.bmp"));
        array[char_to_index(cast(u8)'+')] = sdl2.LoadBMP(strings.clone_to_cstring("assets/font/+.bmp"));
        array[char_to_index(cast(u8)'?')] = sdl2.LoadBMP(strings.clone_to_cstring("assets/font/question_mark.bmp"));
        array[char_to_index(cast(u8)'!')] = sdl2.LoadBMP(strings.clone_to_cstring("assets/font/exclamation_mark.bmp"));
        array[char_to_index(cast(u8)',')] = sdl2.LoadBMP(strings.clone_to_cstring("assets/font/comma.bmp"));
        array[char_to_index(cast(u8)'.')] = sdl2.LoadBMP(strings.clone_to_cstring("assets/font/period.bmp"));
        array[char_to_index(cast(u8)'\'')] = sdl2.LoadBMP(strings.clone_to_cstring("assets/font/apostrophe.bmp"));
        array[char_to_index(cast(u8)'"')] = sdl2.LoadBMP(strings.clone_to_cstring("assets/font/quotation_double.bmp"));
    };
    load_quill :: proc (array_ref:^[LENGTH_OF_QUILL_ARRAY]^sdl2.Surface ){
        for x, idx in array_ref {
            temp_directory:[32]byte;
            temp_dir := fmt.bprintf(temp_directory[:], "assets/quill/quill_%c.bmp", '1' + idx);
            fmt.printf("tempdir -> %s \n", temp_dir)
            x = sdl2.LoadBMP(strings.clone_to_cstring(temp_dir));
        };
    };
    load_item_in_view_surfaces :: proc (item_in_view_sprites:^[ITEM_ENUMS][VIEW_ENUMS]^sdl2.Surface ){
        for x, view_idx in item_in_view_sprites {
            for _x, item_idx in x {
                temp_directory:[64]byte;
                temp_dir := fmt.bprintf(temp_directory[:], "assets/%s_item_%s.bmp", reflect.enum_string(view_idx), reflect.enum_string(item_idx));
                //Limitation: Only one place for an item in any room.
                //Only address if relevant.
    
                item_in_view_sprites[view_idx][item_idx] = sdl2.LoadBMP(strings.clone_to_cstring(temp_dir));
                if(item_in_view_sprites[view_idx][item_idx] == nil){
                    continue;
                }
                switch(reflect.enum_string(item_idx)){
                    case "AXE":
                        item_in_view_sprites[view_idx][item_idx].clip_rect.x = 242;
                        item_in_view_sprites[view_idx][item_idx].clip_rect.y = 113;
                    case "LAZARUS_ICON":
                        item_in_view_sprites[view_idx][item_idx].clip_rect.x = 117;
                        item_in_view_sprites[view_idx][item_idx].clip_rect.y = 63;
                }
            };
        };
    };
    
    load_npc_surfaces :: proc (gs:^GlobalSurfaces) {
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
        for x, idx in gs.npc_portraits {
            temp_directory:[64]byte;
            temp_dir := fmt.bprintf(temp_directory[:], "assets/%s_PORTRAIT.bmp", reflect.enum_string(idx));
            gs.npc_portraits[idx] = sdl2.LoadBMP(strings.clone_to_cstring(temp_dir))
            if(gs.npc_portraits[idx] != nil){
                point := default_npc_portrait_point(idx);
                gs.npc_portraits[idx].clip_rect.x = point.x;
                gs.npc_portraits[idx].clip_rect.y = point.y;
            };
            mem.zero(&temp_directory, len(temp_directory));
            temp_dir = fmt.bprintf(temp_directory[:], "assets/%s_STANDING.bmp", reflect.enum_string(idx));
            gs.npc_standing[idx] = sdl2.LoadBMP(strings.clone_to_cstring(temp_dir))
            if(gs.npc_standing[idx] != nil){
                point := default_npc_standing_point(idx);
                gs.npc_standing[idx].clip_rect.x = point.x;
                gs.npc_standing[idx].clip_rect.y = point.y;
            };
        };
    };

	load_views(&ge.surfs.view_background_surfaces)
	load_font_files(&ge.surfs.font_surface_array)
	load_quill(&ge.surfs.quill_array)
    fmt.printf("oweghi2\n")
    load_item_in_view_surfaces(&ge.surfs.item_in_view_surfaces)
    fmt.printf("oweghi4\n")
    load_npc_surfaces(&ge.surfs)
    fmt.printf("oweghi3\n")
    ge.surfs.font_rect = ge.surfs.font_surface_array[0].clip_rect
    // Done


	game_mode = ._Default
    fmt.printf("oweghi")
}



parse_token :: proc(str:string) -> ValidCommand {
	switch(str){
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

TextBufferData :: struct {
    elems_in_charBuffer:int,
    charBuffer:[LENGTH_OF_CHAR_BUFFER_ARRAY]u8,
    tokenBuffer:[]string, //TODO: Rename TokenBuffer to tokens or something
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

ITEM_ENUMS :: enum {
    AXE,
    LAZARUS_ICON,
    CHRIST_ICON,
    MARY_ICON,
    JBAPTIST_ICON,
}

InventoryItem_ListElem :: struct {
    item_enum:ITEM_ENUMS,
    next_item_index:int, // -1 = tail
};

MAX_ITEMS_IN_INVENTORY :: 12

PlayerInventory :: struct {
    inv_item:[MAX_ITEMS_IN_INVENTORY]InventoryItem_ListElem,
    occupied:[MAX_ITEMS_IN_INVENTORY]bool,
    tail_index:int,
    origin_index:int,
    number_of_items_held:int,
};

PlayerItemData :: struct {
    item_description:[ITEM_ENUMS]string,
    is_takeable_item:[ITEM_ENUMS]bool,
    is_item_taken:[ITEM_ENUMS]bool,
    current_room_location:[ITEM_ENUMS]Maybe(VIEW_ENUMS),
    number_of_items_in_view:[VIEW_ENUMS]int,
    index_within_inventory:[ITEM_ENUMS]int,
    synonyms:[ITEM_ENUMS][MAX_NUMBER_OF_SYNONYMS]string,
};

PlaceEvent :: struct {
    scenery_dest_index:int,
    event:proc (^PlayerItemData, ^SceneryItemData),
};


EventData :: struct {
    //These will very likely need to be made multi-dimensional.
    take_events:[ITEM_ENUMS]proc (^PlayerItemData, ^SceneryItemData),
    place_events:[ITEM_ENUMS]PlaceEvent,
};

Item_State :: struct {
    inv:PlayerInventory,
    items:PlayerItemData,
    events:EventData,
};

check_item_synonyms :: proc (str:string, pid:^PlayerItemData) -> (ITEM_ENUMS, bool) {
    //TODO: This is broken, fix later
    // for i, idx in pid.synonyms {
    //     for j in 0..<MAX_NUMBER_OF_SYNONYMS {
    //         if str == pid.synonyms[idx][j] do return idx, true
    //     };
    // };
    return nil, false
};

item_name_to_index :: proc (str:string, pid:^PlayerItemData) -> (item_enum:ITEM_ENUMS, ok:bool) {
    item_enum, ok = reflect.enum_from_name(ITEM_ENUMS, str)
    if(ok){
        return item_enum, ok
    }
    return check_item_synonyms(str, pid)
};

scenery_item_name_to_index :: proc (name:string, scenery_items:^SceneryItemData) -> int{
    for  i in 0..=scenery_items.number_of_items {
        fmt.printf("name %v , item name %v", name, scenery_items.item_name[i])
        if name == scenery_items.item_name[i] do return i
    };
    fmt.printf("Cannot find scenery item")
    return -1;
};

 SaveData :: struct {// Initialised with new game state
    res_index:int,
    item_data: PlayerItemData,
    inventory_data: PlayerInventory,
    view_data:ViewData,
};
SAVEGAME_IO :: enum {
    READ,
    WRITE,
};

handle_savegame_io :: proc (mode:SAVEGAME_IO, save_data:^SaveData){

    io_func := mode == .WRITE ? os.write : os.read

    saveFileHandle, err := os.open("save.dat", mode == .WRITE ? os.O_WRONLY : os.O_RDONLY);
    fmt.printf("Err in handlefunc? -> %v", err)
    items_handled := 0;
    errno:os.Errno


    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes (save_data.res_index));
    //Room item data
    
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.item_data.index_within_inventory));
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.item_data.is_item_taken));
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.item_data.is_takeable_item));
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.item_data.item_description));
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.item_data.number_of_items_in_view));
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.item_data.current_room_location));
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.item_data.synonyms));

    //Inventory Data
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.inventory_data.inv_item));
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.inventory_data.number_of_items_held));
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.inventory_data.occupied));
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.inventory_data.origin_index));
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.inventory_data.tail_index));

    //Room Data
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.view_data.current_view_idx));
    items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.view_data.npc_in_room));

    for i in VIEW_ENUMS{
        items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.view_data.scenery_items[i].item_description));
        items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.view_data.scenery_items[i].item_name));
        items_handled, errno = io_func(saveFileHandle, mem.any_to_bytes(save_data.view_data.scenery_items[i].number_of_items));
    };

    os.close(saveFileHandle);
};

u8RGB_To_u32_RGB888 :: proc (R,G,B:u8) -> u32 {return (cast(u32)R << 16) | (cast(u32)G << 8) | cast(u32)B}

// #define RedOf(hexRGB888) ((hexRGB888 >> 16) & 255)
// #define GreenOf(hexRGB888) ((hexRGB888 >> 8) & 255)
// #define BlueOf(hexRGB888) (hexRGB888 & 255)

RedOf :: proc (hexRGB888:u32) -> u8 {return u8(hexRGB888 >> 16) & 255}
GreenOf :: proc (hexRGB888:u32) -> u8 {return u8(hexRGB888 >> 8) & 255}
BlueOf :: proc (hexRGB888:u32) -> u8 {return u8(hexRGB888 & 255)}



NUMBER_OF_PALETTES :: 3 //TODO: This is wrong! Only accidentally correct!

//TODO: Oh no! Number of palettes is implicitly wrong!
replace_all_palettes :: proc (gs:^GlobalSurfaces, room_palettes:[VIEW_ENUMS]^[4]u32, new_room_pal_index:VIEW_ENUMS){
    replace_palette :: proc (target:^sdl2.Surface, current_palette:^[4]u32, new_palette:^[4]u32){
        // uint32_t* pixel_ptr = (uint32_t*)target.pixels;
        pixel_ptr := cast(^u32)target.pixels
        for i in 0..< target.h * target.w {
            red, green, blue:u8 = 0, 0, 0;
            sdl2.GetRGB(pixel_ptr^,target.format,&red,&green,&blue);
            detected_colour :u32 = u8RGB_To_u32_RGB888(red,green,blue)
            for colour, j in current_palette{
                replace_color := current_palette[j];
                if(detected_colour == replace_color){
                    new_color := new_palette[j];
                    pixel_ptr^ = sdl2.MapRGB(target.format,RedOf(new_color),GreenOf(new_color),BlueOf(new_color));
                };
            };
            pixel_ptr = mem.ptr_offset(pixel_ptr, 1)
    
        };
    };

    for pal_index in VIEW_ENUMS{
        for f, i in gs.font_surface_array{
            char_sprite := gs.font_surface_array[i];
            if(char_sprite == nil){continue;};
            replace_palette(char_sprite, room_palettes[pal_index], room_palettes[new_room_pal_index]);
        };
        for p, i in gs.quill_array{
            replace_palette(gs.quill_array[i], room_palettes[pal_index], room_palettes[new_room_pal_index]);
        };
        for npc, i in gs.npc_portraits {
            replace_palette(gs.npc_portraits[i], room_palettes[pal_index], room_palettes[new_room_pal_index]);
            replace_palette(gs.npc_standing[i], room_palettes[pal_index], room_palettes[new_room_pal_index]);
        };
    };
};

handle_default_mode_event :: proc (event:^sdl2.Event, t:^TextBufferData, game_mode:^GameMode){


    if (event.type == .TEXTINPUT){
        if (t.elems_in_charBuffer == LENGTH_OF_CHAR_BUFFER_ARRAY - 1){return;};
        char_to_put :u8; 
        char_to_parse := event.text.text[0];
        if(char_to_index(char_to_parse) >= 0){
            char_to_put = char_to_parse;
        } else {return;};
        t.charBuffer[t.elems_in_charBuffer] = char_to_put;
        t.elems_in_charBuffer += 1;
        fmt.printf("Chars in buffer:[%s] Length %i\n", t.charBuffer, t.elems_in_charBuffer);
    };

    if(event.type != .KEYDOWN){return;};

    if(event.key.keysym.sym == .BACKSPACE){
        if (t.elems_in_charBuffer == 0){
            return;
        };
        t.charBuffer[t.elems_in_charBuffer - 1] = 0
        t.elems_in_charBuffer -= 1;
        fmt.printf("Chars in buffer:[%s] Length %i\n", t.charBuffer, t.elems_in_charBuffer);
    };
    if(event.key.keysym.sym == .RETURN){
        //Submit the buffer for command parsing
        for char in &t.charBuffer {
            switch(char){
                case 'a'..='z': 
                    char -= 32
            }
        }
        // can then use 's' as a 'string'.
       
        honk := string(t.charBuffer[0:t.elems_in_charBuffer])
        t.tokenBuffer = strings.split(honk, " ")
        fmt.printf("Tokens in buffer: ")
        for token in t.tokenBuffer {
            fmt.printf("%s ,", token)
        }
        fmt.printf("\n")
        return;
    };

};

addTxtAnim :: proc (arr:^Text_RenderState, anim: proc (int, ^GlobalSurfaces, string) -> int, temp_data:Maybe(string)){
    arr.current_txt_anim = anim;
    arr.duration_count = 240;
    if(temp_data == nil){return;} //TODO: investigate this nil
    for i in 0..<5 {
        for j in 0..<LENGTH_OF_CHAR_BUFFER_ARRAY {
            arr.temp_data = temp_data.(string)
        };
    };
};

blit_text :: proc (gs:^GlobalSurfaces, string_to_blit:string, YPosition:i32, XPosition:i32){
    // max_i := 0

    //     for i, idx in string_to_blit {
    //         if i == 0 {
    //             max_i = idx ;break
    //         }
    //     }    
    


    space_rect:sdl2.Rect  
    space_rect.h = gs.font_rect.h; space_rect.w = gs.font_rect.w;
    space_rect.y = YPosition;
    for i in 0..<len(string_to_blit){
        space_rect.x = i32(i) * 9 + XPosition;
        // fmt.printf("in loop, %i\n", i)
        // fmt.printf("String to blit %c , index %i , char_to_index %i , len %i", string_to_blit[i], i, char_to_index(string_to_blit[i]), max_i)
        char_to_blit_idx := char_to_index(string_to_blit[i])
        if (char_to_blit_idx == -1){continue}
        sdl2.BlitSurface(gs.font_surface_array[char_to_blit_idx], nil, gs.working_surface, &space_rect);
    };
};

save_animation :: proc (duration:int, gs:^GlobalSurfaces, _:string) -> int{
    blit_text(gs, "+GAME SAVED+", 0, (gs.font_rect.w * 13) );
    return duration == 0 ? -1 : duration - 1
};

// TODO: Pointer to a pointer? Bruh
handle_menu_mode_event :: proc (event:^sdl2.Event, window:^sdl2.Window, render_surface:^^sdl2.Surface, game_mode:^GameMode, menu_state:^Menu_RenderState, animation_arrays:^Text_RenderState, save_data:^SaveData){
    if(event.type != .KEYDOWN){return;};
    if(event.key.keysym.sym == .UP){
        if (menu_state.selected_option_index == 0){return;}
        menu_state.selected_option_index -= 1;
    };
    if(event.key.keysym.sym == .DOWN){
        if (menu_state.selected_option_index == 2){return;}
        menu_state.selected_option_index += 1;
    };

    if(event.key.keysym.sym == .RETURN){
        if(menu_state.selected_option_index == 2){
            game_mode^ = ._Default;
            menu_state.res_option_index = menu_state.prev_res_option_index;
        };
        if(menu_state.selected_option_index == 1){
            save_data.res_index = menu_state.res_option_index;
            handle_savegame_io(.WRITE, save_data);
            addTxtAnim(animation_arrays, save_animation,  nil);
            game_mode^ = ._Default;
        };
    };

    if(menu_state.selected_option_index == 0){
        if(event.key.keysym.sym == .LEFT){
            if (menu_state.res_option_index == 0){return;}
            menu_state.res_option_index -= 1;
        };
        if(event.key.keysym.sym == .RIGHT){
            if (menu_state.res_option_index == 4){return;}
            menu_state.res_option_index += 1;
        };
        if(event.key.keysym.sym == .RETURN){
            if (menu_state.prev_res_option_index == menu_state.res_option_index){return;}
            menu_state.prev_res_option_index = menu_state.res_option_index;
            sdl2.SetWindowSize(window, i32(NATIVE_WIDTH * (menu_state.res_option_index + 1)), i32(NATIVE_HEIGHT * (menu_state.res_option_index + 1)));
            render_surface^ = sdl2.GetWindowSurface(window);
        };
    };
};

handle_dialogue_mode_event :: proc ( event:^sdl2.Event, npc_rs:^NPC_RenderState, game_mode:^GameMode){
    if(event.type != .KEYDOWN){return;};
    
    if(event.key.keysym.sym == .RETURN){
        if(npc_rs.current_node.number_of_child_nodes == 0){
            game_mode^ = ._Default;
            return;
        };
        npc_rs.current_node = npc_rs.current_node.child_nodes[npc_rs.selected_dialogue_option];
        npc_rs.number_of_options = npc_rs.current_node.number_of_child_nodes;
        npc_rs.selected_dialogue_option = 0;
        return;
    };
    
    if(event.key.keysym.sym == .UP){
        if(npc_rs.current_node.child_nodes[1] != nil){
            if(npc_rs.selected_dialogue_option != 0){
                npc_rs.selected_dialogue_option -= 1;
            };
        };
    };
    if(event.key.keysym.sym == .DOWN){
        if(npc_rs.current_node.child_nodes[1] != nil){
            if(npc_rs.selected_dialogue_option != (npc_rs.number_of_options - 1)){
                npc_rs.selected_dialogue_option += 1;
            };
        };
    };
};

handle_inventory_mode_event :: proc (event:^sdl2.Event, game_mode:^GameMode, inv_state:^Inventory_RenderState){
    if(event.type != .KEYDOWN){return;};
    if(event.key.keysym.sym == .UP){
        if(inv_state.row_selected == 0){return;}
        inv_state.row_selected -= 1;
    }
    if(event.key.keysym.sym == .DOWN){
        fmt.printf("Row selected before attempting increment -> %i", inv_state.row_selected);
    if(inv_state.row_selected == (MAX_ITEMS_IN_INVENTORY / 2)){return;}
        inv_state.row_selected += 1;
    if(inv_state.row_selected == (MAX_ITEMS_IN_INVENTORY / 2)){
            inv_state.left_column_selected = true;
        };
    };
    if(event.key.keysym.sym == .LEFT){
        inv_state.left_column_selected = true;
    };
    if(event.key.keysym.sym == .RIGHT){
        if(inv_state.row_selected == (MAX_ITEMS_IN_INVENTORY / 2)){
            return;
        };
        inv_state.left_column_selected = false;
    };
    if(event.key.keysym.sym == .RETURN){
        if(inv_state.row_selected == (MAX_ITEMS_IN_INVENTORY / 2)){
            game_mode^ = ._Default;
        };
    };
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

parse_look_modifier :: proc ( str:string) -> LookModifier{
    switch(str){
        case "IN", "WITHIN", "INSIDE": return ._LookInside;
    }
    return ._DefaultLook;
}

inventory_add_item :: proc (inv:^PlayerInventory, new_item:ITEM_ENUMS) -> int {
    new_inv_item:InventoryItem_ListElem;
    new_inv_item.item_enum = new_item;
    new_inv_item.next_item_index = -1;

    if(inv.tail_index == -1){
        inv.inv_item[0] = new_inv_item;
        inv.occupied[0] = true;
        inv.tail_index = 0;
        inv.origin_index = 0;
        inv.number_of_items_held +=1 ;
        return 0;
    };
    for i in 0..< MAX_ITEMS_IN_INVENTORY {
        if(inv.occupied[i] == true){continue;};
        inv.inv_item[inv.tail_index].next_item_index = i;
        inv.tail_index = i;
        inv.occupied[i] = true;
        inv.inv_item[i] = new_inv_item;
        inv.number_of_items_held +=1;
        return i;
    };
    //All slots occupado
    return -1;
};

inventory_delete_item :: proc ( inv:^PlayerInventory, deletion_index:int) -> int {
    if(deletion_index == inv.origin_index){
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
        inv.tail_index = i;
        mem.zero(&inv.inv_item[deletion_index], 1)
        inv.occupied[deletion_index] = false;
        inv.number_of_items_held -= 1;
        return 0;
    };
    //All slots occupado
    return -1;
};

// GlobalEverything :: struct {
//     settings:GameSettings,
//     surfs:GlobalSurfaces,
//     view_data:ViewData,
//     game_mode:GameMode,
// };

handle_command :: proc (command:ValidCommand, 
    ge:^GlobalEverything,
    global_render:^GlobalRenderStates, 
    save_data:^SaveData, 
    item_state:^Item_State,
    text_buffer:^TextBufferData, 
    dialogue_data:^DialogueData, 
    room_palettes:[VIEW_ENUMS]^[4]u32,
    ){
        using ge;
        one_liner ::  proc (duration:int, payload:^GlobalSurfaces,  str:string) -> int {
            blit_tile(payload.font_surface_array[char_to_index(u8(' '))],LENGTH_OF_CHAR_BUFFER_ARRAY + 4,payload.working_surface, (NATIVE_HEIGHT) - payload.font_rect.h* 2, 0); 
            blit_text(payload, str, (NATIVE_HEIGHT) - payload.font_rect.h* 2, 0);        
            return duration == 0 ? -1 : duration - 1;            
        } 
        switch(command){

            case .Save: 
                save_data.res_index = global_render.menu.res_option_index;
                save_data.view_data.current_view_idx = view_data.current_view_idx;
                save_data.item_data = item_state.items;
                save_data.inventory_data = item_state.inv;
                save_data.view_data.npc_in_room = view_data.npc_in_room
                save_data.view_data.scenery_items = view_data.scenery_items
                handle_savegame_io(.WRITE, save_data);
                addTxtAnim(&global_render.txt, save_animation,  nil);
            case .Menu: game_mode = ._Menu; 
            case .Quit: sdl2.PushEvent(&sdl2.Event{type = .QUIT});
            case .Go: 
                if (len(text_buffer.tokenBuffer) == 1) {addTxtAnim(&global_render.txt, one_liner, "Where would you like to go?");break;};
                new_index, ok := reflect.enum_from_name(VIEW_ENUMS, text_buffer.tokenBuffer[1]);
                if (new_index == view_data.current_view_idx){addTxtAnim(&global_render.txt, one_liner, "You're already here!");break;};

                ok = view_data.adjascent_views[view_data.current_view_idx][new_index];
                switch ok {
                    case false:
                        addTxtAnim(&global_render.txt, one_liner,  fmt.aprintf( "'%s' isn't near here.", text_buffer.tokenBuffer[1]));
                    case true:
                        if(view_data.view_type[new_index] != .Room){addTxtAnim(&global_render.txt, one_liner, "You cannot fit in there!"); break;}
                        global_render.txt.duration_count = 0; view_data.current_view_idx = new_index;
                        replace_all_palettes(&surfs, room_palettes, new_index);
                }
            case .Look:{
                if(len(text_buffer.tokenBuffer) == 1){addTxtAnim(&global_render.txt, one_liner, "What would you like to look at?");break;};
                switch(parse_look_modifier(text_buffer.tokenBuffer[1])){
                    case ._LookInside: {
                        if(len(text_buffer.tokenBuffer) == 2){addTxtAnim(&global_render.txt, one_liner, "What would you like to look in?"); break;};
                        if text_buffer.tokenBuffer[2] == "INVENTORY"{game_mode = ._Inventory;break;};
                        new_index, ok := reflect.enum_from_name(VIEW_ENUMS, text_buffer.tokenBuffer[1]);;
                        if(ok && view_data.view_type[new_index] == .LookInside){
                            global_render.txt.duration_count = 0; view_data.current_view_idx = new_index;
                        };
                        addTxtAnim(&global_render.txt, one_liner, "Cannot look inside there.");
                    };
                    case ._DefaultLook:
                        if(text_buffer.tokenBuffer[1] == "INVENTORY"){game_mode = ._Inventory;break;};
                        item_index, ok := item_name_to_index(text_buffer.tokenBuffer[1], &item_state.items);
                        if(ok){
                            fmt.printf("pinging on item %s %i",text_buffer.tokenBuffer[1], item_index );
                            addTxtAnim(&global_render.txt, one_liner, item_state.items.item_description[item_index]);
                            break;
                        };
                        _item_index := scenery_item_name_to_index(text_buffer.tokenBuffer[1], &view_data.scenery_items[view_data.current_view_idx]);
                        fmt.printf("Current view: %v", reflect.enum_string(view_data.current_view_idx))
                        if(_item_index != -1){
                            new_string:[5]string
                            fmt.printf("pinging on item %s %i",text_buffer.tokenBuffer[1], _item_index );
                            // for str in &new_string {
                            //    str = vd.scenery_items[vd.current_view_idx].item_description[_item_index][i]
                            // };
                            addTxtAnim(&global_render.txt, one_liner, "TEST - Scenery Item Look");
                            break;
                        };
                        npc_index, _ok := reflect.enum_from_name(NPC_ENUM, text_buffer.tokenBuffer[1])
                        
                        if(_ok && view_data.npc_in_room[view_data.current_view_idx] == npc_index){
                            new_string:[5]string
                            // for str in &new_string {
                            //     str = vd.npc_description[npc_index][i]
                            // };
                            addTxtAnim(&global_render.txt, one_liner, "TEST - Success NPC Look");
                        } else {
                            addTxtAnim(&global_render.txt, one_liner, fmt.aprintf("Cannot find the '%s'.", text_buffer.tokenBuffer[1]));
                        }
    
                    }

            };
            case .Take:{
                if(len(text_buffer.tokenBuffer) == 1 ){
                    addTxtAnim(&global_render.txt, one_liner, "What would you like to take?");
                    break;
                };
                item_index, ok := item_name_to_index(text_buffer.tokenBuffer[1], &item_state.items);
                if(!ok || item_state.items.current_room_location[item_index] != view_data.current_view_idx){
                    addTxtAnim(
                        &global_render.txt, 
                        one_liner, 
                         
                        fmt.aprintf( "Cannot find the '%s'.", text_buffer.tokenBuffer[1]));
                    break;
                };
                item_state.items.is_item_taken[item_index] = true;
                item_state.items.current_room_location[item_index] = nil;
                item_state.items.number_of_items_in_view[view_data.current_view_idx] -=1;
                item_state.items.index_within_inventory[item_index] = inventory_add_item(&item_state.inv, item_index); // likely to be taken out

                if(view_data.events[view_data.current_view_idx].take_events[item_index] != nil){
                    view_data.events[view_data.current_view_idx].take_events[item_index](&item_state.items, &view_data.scenery_items[view_data.current_view_idx]);
                };
                addTxtAnim(
                    &global_render.txt, 
                    one_liner, 
                     
                    fmt.aprintf( "You take the '%s'.", text_buffer.tokenBuffer[1]));
            };
              case .Place:{
                if len(text_buffer.tokenBuffer) == 1 {
                    addTxtAnim(&global_render.txt, one_liner, "What would you like to place?");
                    break;
                };

                item_enum, ok := item_name_to_index(text_buffer.tokenBuffer[1], &item_state.items);
                index_within_inventory := item_state.items.index_within_inventory[item_enum];

                if(!ok || index_within_inventory == -1){
                    addTxtAnim(
                        &global_render.txt, 
                        one_liner, 
                         
                        fmt.aprintf( "You have no '%s'.", text_buffer.tokenBuffer[1]));
                    break;
                };

                if len(text_buffer.tokenBuffer) == 2 {
                    addTxtAnim(&global_render.txt, one_liner, "Where would you like to place it?");
                    break;
                };
                destination_index := scenery_item_name_to_index(text_buffer.tokenBuffer[2], &view_data.scenery_items[view_data.current_view_idx]);
                if(destination_index == -1){
                    addTxtAnim(
                        &global_render.txt, 
                        one_liner, 
                         
                        fmt.aprintf( "Cannot find the '%s'.", text_buffer.tokenBuffer[1]));
                    break;
                };
                if(view_data.events[view_data.current_view_idx].place_events[item_enum].scenery_dest_index != destination_index){
                    addTxtAnim(&global_render.txt, one_liner, "You can't place that there.");
                    break;
                };
                if(view_data.events[view_data.current_view_idx].place_events[item_enum].event != nil){
                    view_data.events[view_data.current_view_idx].place_events[item_enum].event(&item_state.items, &view_data.scenery_items[view_data.current_view_idx]);
                }
                // printf("Item %i desc is now %s \n", item_enum, item_state.items.item_description[_i_AXE][0]);
                fmt.printf("what %i \n", item_state.items.is_item_taken[item_enum]);
                item_state.items.is_item_taken[item_enum] = false;
                item_state.items.current_room_location[item_enum] = view_data.current_view_idx;
                item_state.items.number_of_items_in_view[view_data.current_view_idx] += 1;
                item_state.items.index_within_inventory[item_enum] = -1;
                inventory_delete_item(&item_state.inv, index_within_inventory);
                addTxtAnim(
                    &global_render.txt, 
                    one_liner, 
                     
                    fmt.aprintf( "The '%s' is placed.", text_buffer.tokenBuffer[1]));
            };
            case .Talk:{
                if len(text_buffer.tokenBuffer) == 1 {
                    addTxtAnim(&global_render.txt, one_liner, "Who would you like to talk to?");
                    break;
                };
                npc_index, ok := reflect.enum_from_name(NPC_ENUM, text_buffer.tokenBuffer[1])
                if(!ok || view_data.npc_in_room[view_data.current_view_idx] != npc_index){
                    addTxtAnim(
                        &global_render.txt, 
                        one_liner, 
                         
                        fmt.aprintf("'%s' is not here.", text_buffer.tokenBuffer[1]));
                    break;
                };
                global_render.npc.current_npc = npc_index;
                global_render.npc.current_node = dialogue_data.starter_nodes[npc_index];
                game_mode = ._Dialogue;
                };break;
            case .Inventory:{
                game_mode = ._Inventory;
            };
            case .ListExits:{
                new_string:[5]string
                room_names:[NUMBER_OF_VIEWS]string;
                for i in VIEW_ENUMS {
                    if(view_data.view_type[i] == .LookInside){continue;};
                    if(view_data.adjascent_views[view_data.current_view_idx][i]){room_names[i] = reflect.enum_string(i);};
                }
                i := 0
                for(i < view_data.adjascent_views_num[view_data.current_view_idx]){
                    for j in VIEW_ENUMS {
                         if (view_data.adjascent_views[view_data.current_view_idx][j] == true){
                            new_string[i] = room_names[j]
                            i+=1;
                    }
                };
                for _, idx in new_string {
                    fmt.printf("Place name that is exit %i: %s \n", i, new_string[i]);
                }

                addTxtAnim(&global_render.txt, one_liner, "TEST - List Exits");
                break;
            };
            
        };
        case .Invalid, .Exit:{};
    }
};
init_player_item_data :: proc ( s:^Item_State, view_data:^ViewData){

    for i in 0..<MAX_ITEMS_IN_INVENTORY {
        s.inv.inv_item[i] = {nil, -1};
        s.inv.occupied[i] = false;
    };
    s.inv.origin_index = -1;
    s.inv.tail_index = -1;
    s.inv.number_of_items_held = 0;

    for i in ITEM_ENUMS {
        s.items.current_room_location[i] = nil;
        s.items.index_within_inventory[i] = -1;
        s.items.is_item_taken[i] = false;
    };

    add_item_to_PlayerItemData :: proc (room_items:^PlayerItemData, 
        name:string, 
        description:string,
        is_takeable:bool,
        room_enum:VIEW_ENUMS,
        ){
        @static  current_number_of_items := 0;
        assert(current_number_of_items < NUMBER_OF_PLAYER_ITEMS);
        i, ok := item_name_to_index(name, room_items);
        assert(ok)
        room_items.item_description[i] = description
        room_items.is_takeable_item[i] = is_takeable;
        fmt.printf("for %s adding to room enum %i\n", name, room_enum);
        room_items.current_room_location[i] = room_enum;
        room_items.number_of_items_in_view[room_enum] += 1
        room_items.index_within_inventory[i] -= 1;
        current_number_of_items += 1;
    
    };

    axe_description := "The axe is stumpwise lodged."
    add_item_to_PlayerItemData(&s.items, "AXE", axe_description, true, .CLEARING);
    s.items.synonyms[.AXE][0] = "HATCHET"

    take_axe_event :: proc (room_items:^PlayerItemData, scenery_items:^SceneryItemData){
        axe_description := 
            "It's a well balanced axe. Much use."
        stump_description :=
            "Stump left behind from an old tree. Memories of childhood return."
        stump_index := scenery_item_name_to_index("STUMP", scenery_items);
        scenery_items.item_description[stump_index] = stump_description
        room_items.item_description[.AXE] = axe_description
    };
    view_data.events[.CLEARING].take_events[.AXE] = take_axe_event;
    axe_in_stump_event:PlaceEvent;
    axe_in_stump_event.scenery_dest_index = scenery_item_name_to_index("STUMP", &view_data.scenery_items[.CLEARING]);
    

    place_axe_in_stump_event :: proc ( room_items:^PlayerItemData,  scenery_items:^SceneryItemData){
         axe_description :=
            "The axe is stumpwise lodged."
         stump_description:= 
            "The stump is axewise stuck."
        stump_index := scenery_item_name_to_index("STUMP", scenery_items);

        room_items.item_description[.AXE] = axe_description
        scenery_items.item_description[stump_index] = stump_description
    };
    
    axe_in_stump_event.event = place_axe_in_stump_event;
    view_data.events[.CLEARING].place_events[.AXE] = axe_in_stump_event;

    lazarus_icon_description :="An icon St Lazarus being raised from the dead by Christ."
    add_item_to_PlayerItemData(&s.items, "LAZARUS_ICON", lazarus_icon_description, true, .SHRINE);
    s.items.synonyms[.LAZARUS_ICON][0] = "ICON";
    s.items.synonyms[.LAZARUS_ICON][1] = "LAZARUS";

    icon_in_shrine_event:PlaceEvent;
    icon_in_shrine_event.scenery_dest_index = scenery_item_name_to_index("SHRINE", &view_data.scenery_items[.SHRINE]);
    view_data.events[.SHRINE].place_events[.LAZARUS_ICON] = icon_in_shrine_event;
}


import "core:runtime"
main :: proc (){
    

	using sdl2;
    if( Init( INIT_VIDEO ) < 0 ){
        fmt.printf( "SDL could not initialize! SDL_Error: %s\n", sdl2.GetError() );
        return;
    } 
    FPS :: 60;
    frameDuration :: 1000 / FPS;
    ge:GlobalEverything;
	init_everything(&ge)
    context.allocator = runtime.default_allocator()
    text_buffer:TextBufferData;

    church_palette: = [4]u32{0xCBF1F5, 0x445975, 0x0E0F21, 0x050314};
    clearing_palette := [4]u32{0xEBE08D, 0x8A7236, 0x3D2D17, 0x1A1006};
    skete_palette := [4]u32{0x8EE8AF, 0x456E44, 0x1D2B19, 0x0B1706};
    room_palettes:[VIEW_ENUMS]^[4]u32 = {
        .CHURCH = &church_palette, 
        .CLEARING = &clearing_palette, 
        .SKETE = &skete_palette, 
        .CHAPEL = &skete_palette, 
        .SHRINE = &church_palette,
    };

    dialogue_data:DialogueData;
    //NOTE: Fix text
    alexei_start:DialogueNode = {
        dialogue_text = "Your time is nigh. ...Repent!",
    };
    alexei_second:DialogueNode = {
        dialogue_text = "...Else into the hole with you!", 
        parent_node = &alexei_start,
    };
    alexei_third_1:DialogueNode = {
        selection_option = "Hole?", 
        dialogue_text = "Yes, hole. The deep hole has many sharp bits. It will be hard to fish you out.",
        parent_node = &alexei_second,
    };
    alexei_third_2:DialogueNode = {
        selection_option = "I'm not repenting.", 
        dialogue_text = "Alexei shakes his head. You're already in deep.",
        parent_node = &alexei_second,
    };
    alexei_dialogue:[4]^DialogueNode = {&alexei_start, &alexei_second, &alexei_third_1, &alexei_third_2};

    init_dialogue_nodes :: proc (nodes:[]^DialogueNode){
        for x, i in nodes {
            if(nodes[i].parent_node == nil){continue;};
            child_node_index := nodes[i].parent_node.number_of_child_nodes;
            nodes[i].parent_node.child_nodes[child_node_index] =  nodes[i];
            nodes[i].parent_node.number_of_child_nodes += 1;
        };
    };
    init_dialogue_nodes(alexei_dialogue[:])

    item_state:Item_State;
    init_player_item_data(&item_state, &ge.view_data);
    //^^^ INIT global stuff here

    saveFileHandle, err := os.open("save.dat", os.O_RDONLY)

    fresh_game := err == os.ERROR_FILE_NOT_FOUND;
    fmt.printf("File error -> %v ", err)
    fmt.printf("New game? %v", fresh_game)
    os.close(saveFileHandle)
    save_data:SaveData
    if (fresh_game){
        createFileHandle, err := os.open("save.dat", os.O_CREATE)
        //Init default save data
        save_data.res_index = 0;
        save_data.item_data = item_state.items;
        save_data.inventory_data = item_state.inv;
        save_data.view_data.current_view_idx =  .CHURCH;
        save_data.view_data.npc_in_room = ge.view_data.npc_in_room
        save_data.view_data.scenery_items = ge.view_data.scenery_items // TODO: Get a database of string information, have runtime & savedata just reverence the data base
        os.close(createFileHandle)
    }
    handle_savegame_io(fresh_game ? .WRITE : .READ, &save_data);

    global_render:GlobalRenderStates
    global_render.menu.res_option_index = 0;
    global_render.menu.prev_res_option_index = 0;

    if (!fresh_game){
        //Read save data
        global_render.menu.res_option_index = save_data.res_index;
        global_render.menu.prev_res_option_index = save_data.res_index;
        item_state.items = save_data.item_data;
        item_state.inv = save_data.inventory_data;
        ge.view_data.current_view_idx = save_data.view_data.current_view_idx;
        ge.view_data.npc_in_room = save_data.view_data.npc_in_room
        ge.view_data.scenery_items = save_data.view_data.scenery_items
    };

    replace_all_palettes(&ge.surfs, room_palettes, save_data.view_data.current_view_idx);

    window := sdl2.CreateWindow("Searching for the Name", 
       	sdl2.WINDOWPOS_UNDEFINED,	sdl2.WINDOWPOS_UNDEFINED, 
        i32(NATIVE_WIDTH * ge.settings.window_size), 
        i32(NATIVE_HEIGHT * ge.settings.window_size), 
        sdl2.WINDOW_SHOWN );
    if( window == nil ){
        fmt.printf( "Window could not be created! SDL_Error: %s\n", sdl2.GetError() );
        return ;
    };

    render_surface := sdl2.GetWindowSurface( window );
    ge.surfs.working_surface = sdl2.CreateRGBSurface(0, NATIVE_WIDTH, NATIVE_HEIGHT, 
        i32(render_surface.format.BitsPerPixel), u32(render_surface.format.Rmask), 
        render_surface.format.Gmask, render_surface.format.Bmask, render_surface.format.Amask);
    //^^^ setup window, render_surface, and working_surface handles here ^^^
	using ge;
    for (settings.quit != true){
		
		sdl2.StartTextInput()
        frameStart := sdl2.GetTicks();
        event:sdl2.Event;
        for( sdl2.PollEvent( &event ) != 0 ){
            if (event.type == .QUIT){settings.quit = true;break;};
            switch(game_mode){
                case ._Default, ._LookInside: handle_default_mode_event(&event, &text_buffer, &game_mode);
                case ._Menu: handle_menu_mode_event(&event,window, &render_surface, &game_mode, &global_render.menu, &global_render.txt, &save_data);
                case ._Dialogue: handle_dialogue_mode_event(&event, &global_render.npc, &game_mode);
                case ._Inventory: handle_inventory_mode_event(&event, &game_mode, &global_render.inv);
				// case ._LookInside: {}
            };
        };
        
        if(len(text_buffer.tokenBuffer) > 0){
            command: = parse_token(text_buffer.tokenBuffer[0]);
            handle_command(command, &ge, &global_render, &save_data, &item_state, &text_buffer, &dialogue_data, room_palettes);
        }

        sdl2.BlitSurface(surfs.view_background_surfaces[view_data.current_view_idx], nil, surfs.working_surface, nil);

        blit_background :: proc ( background:^sdl2.Surface, working_surface:^sdl2.Surface){
            sdl2.BlitSurface(background, nil, working_surface, nil);
        };

        blit_items_in_view :: proc (
            view_index:VIEW_ENUMS, 
            gs:^GlobalSurfaces,
            room_item_data:^PlayerItemData){
            for i in ITEM_ENUMS {
                if(room_item_data.is_item_taken[i]){continue;}
                item_sprite := gs.item_in_view_surfaces[i][view_index];
                if(item_sprite == nil){continue;};
                sdl2.BlitSurface(item_sprite, nil, gs.working_surface, &item_sprite.clip_rect);
            };
        };

        blit_background(ge.surfs.view_background_surfaces[ge.view_data.current_view_idx], ge.surfs.working_surface);
        blit_items_in_view(ge.view_data.current_view_idx, &ge.surfs, &item_state.items);

        switch(game_mode){
            case ._Inventory: {};
            case ._Menu: {};
            case ._Dialogue: {};
            case ._Default, ._LookInside: {
                blit_npcs_in_room :: proc (current_room_index:VIEW_ENUMS, gs:^GlobalSurfaces, view_data:^ViewData){
                    if(view_data.npc_in_room[current_room_index] == nil){return;}
                    npc_surface := gs.npc_standing[view_data.npc_in_room[current_room_index].(NPC_ENUM)];
                    sdl2.BlitSurface(npc_surface, nil, gs.working_surface, &npc_surface.clip_rect);
                };
                DoTextAnimations :: proc ( arr:^Text_RenderState, tap:^GlobalSurfaces){
                    if(arr.current_txt_anim == nil){
                        return;
                    }
                    new_count := arr.current_txt_anim(arr.duration_count, tap, arr.temp_data);
                    if(new_count == -1){
                        mem.zero_item(&arr.current_txt_anim)
                        mem.zero_item(&arr.current_txt_anim);
                        mem.zero_item(&arr.duration_count);
                        mem.zero_item(&arr.temp_data);
                    };
                    arr.duration_count = new_count;
                };
                

                blit_npcs_in_room(view_data.current_view_idx, &ge.surfs, &view_data);

                DoTextAnimations(&global_render.txt, &ge.surfs);
                if (text_buffer.elems_in_charBuffer == 0){break}
                blit_tile(
                    ge.surfs.font_surface_array[char_to_index(u8(' '))],
                    LENGTH_OF_CHAR_BUFFER_ARRAY + 4, 
                    ge.surfs.working_surface, 
                    (ge.surfs.font_rect.h * -1) + NATIVE_HEIGHT, 
                    0);
                blit_text(
                    &ge.surfs, 
                    string(text_buffer.charBuffer[:]), 
                    (ge.surfs.font_rect.h * -1) + NATIVE_HEIGHT, 
                    0);

                animate_quill :: proc (gs:^GlobalSurfaces, elems_in_charBuffer:int){
                    @static animation_frame := 0;
                    @static counter := 0;
                    counter += 1
                    if (counter == 30) {
                        animation_frame = animation_frame == 3 ? 0 : animation_frame + 1;
                        counter = 0;
                    };
                    blit_tile(
                        gs.quill_array[animation_frame],
                        1, gs.working_surface, 
                        i32((gs.quill_array[0].clip_rect.h * -1) + NATIVE_HEIGHT), 
                        i32((gs.quill_array[0].clip_rect.w + 1) * i32(elems_in_charBuffer)));
                };

                if(text_buffer.elems_in_charBuffer != 35){animate_quill(&ge.surfs, text_buffer.elems_in_charBuffer);};          
            };
        }

        sdl2.BlitScaled(surfs.working_surface, nil, render_surface, nil);
        sdl2.UpdateWindowSurface(window);
        frameTime := sdl2.GetTicks() - frameStart;
        if(len(text_buffer.tokenBuffer) > 0){
                mem.zero_item(&text_buffer)
        }
        if (frameDuration > frameTime){
			sdl2.Delay(frameDuration - frameTime);
        };
    };

    //Cleanup
    sdl2.Quit();

    return ;
}
