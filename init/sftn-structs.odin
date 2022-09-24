package init;

Point_i32 :: struct {
    x:i32,
    y:i32,
}

ViewData :: struct {
    current_view_idx: VIEW_ENUM, 
    npc_in_room:[VIEW_ENUM]Maybe(NPC_ENUM),
    npc_description:[NPC_ENUM]string,
    scenery_items:SceneryItemData, //thonk
    events:[VIEW_ENUM]EventData,
    view_type:[VIEW_ENUM]ViewType,
    adjascent_views:[VIEW_ENUM]bit_set[VIEW_ENUM], // adjascent_views[view_to_query][is_this_adjascent]
};

SceneryItemData :: struct {
	sceneryItemNames:[VIEW_ENUM][dynamic]string,
	enum_state:[VIEW_ENUM][dynamic]int,
	descriptions:[VIEW_ENUM][dynamic][]string,
}

PlaceEvent :: struct {
    scenery_dest_index:int,
    event:proc (^GlobalEverything),
};
EventData :: struct {
    //These will very likely need to be made multi-dimensional.
    take_events:[PLAYER_ITEM]proc (^GlobalEverything),
    place_events:[PLAYER_ITEM]PlaceEvent,
};

import "vendor:sdl2";
LENGTH_OF_QUILL_ARRAY :: 4
GlobalSurfaces :: struct {
    working_surface:^sdl2.Surface ,
    font_surface_array:[96]^sdl2.Surface,
    view_background_surfaces:[VIEW_ENUM]^sdl2.Surface,
    quill_array:[4]^sdl2.Surface,
    // Better solution needed, to get rid of dead data? Irrelevant for now?
    item_in_view_surfaces:[PLAYER_ITEM][VIEW_ENUM]^sdl2.Surface, // should be dynamic array of {init.VIEW_ENUM, PLAYER_ITEM, STATE_INT}
    item_points_view_location:[PLAYER_ITEM][VIEW_ENUM]Point_i32,
    npc_portraits:[NPC_ENUM]^sdl2.Surface,
    npc_standing:[NPC_ENUM]^sdl2.Surface,
    font_rect: sdl2.Rect,
};

GameSettings :: struct {
    window_size:int, // default = 1
    quit:bool, // default = false
};


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
Synonyms :: struct {
	synonym:[dynamic]string, //use this to find index for below
	scenery_item:[dynamic][]Synonym_SceneryItem, // slice of room enums, and slice of scenery item names
	player_item:[dynamic][]PLAYER_ITEM,
}
Synonym_SceneryItem :: struct {
	name:string,
	view:VIEW_ENUM,
}
Item_State :: struct {
    player_inv:PlayerInventory,
    player_items:PlayerItemData,
    events:EventData,
};

GlobalEverything :: struct {
    settings:GameSettings,
    surfs:GlobalSurfaces,
    view_data:ViewData,
    game_mode:GameMode,
    palettes:[PALETTE][4]u32,
    room_palettes:[VIEW_ENUM]^[4]u32,
    dialogue_data:DialogueData,
    item_state:Item_State,
    render_states:GlobalRenderStates,
    synonyms:Synonyms,
    save_data:SaveData,
};

SaveData :: struct {
    res_index:int,
    view_data: struct {
        current_view_idx:VIEW_ENUM,
        npc_in_room:[VIEW_ENUM]Maybe(NPC_ENUM),
        scenery_items: struct {
            enum_state:[VIEW_ENUM][dynamic]int,
        },
        adjascent_views:[VIEW_ENUM]bit_set[VIEW_ENUM],
    },
    item_data: struct {
        current_description:[PLAYER_ITEM]int,
        is_item_taken:bit_set[PLAYER_ITEM],
        in_view_data: struct {
            enum_state: [PLAYER_ITEM]int,
            view_location:[PLAYER_ITEM]Maybe(VIEW_ENUM),
            is_takeable_item:bit_set[PLAYER_ITEM], 
        },
        inventory_data : struct {
            index_in_inventory:[PLAYER_ITEM]int,
        },
    },
    player_inventory: PlayerInventory,
}

DialogueData :: struct {
    starter_nodes:[NPC_ENUM]^DialogueNode,
};

MAX_ITEMS_IN_INVENTORY :: 12
InventoryItem_ListElem :: struct {
    item_enum:PLAYER_ITEM,
    next_item_index:i8, // -1 = tail
};

PlayerInventory :: struct {
    inv_item:[MAX_ITEMS_IN_INVENTORY]InventoryItem_ListElem,
    occupied:[MAX_ITEMS_IN_INVENTORY]bool,
    tail_index:i8,
    origin_index:i8,
    number_of_items_held:int,
};

PlayerItemData_InView :: struct {
	enum_state:[PLAYER_ITEM]int,
	descriptions:[PLAYER_ITEM][]string,
	view_location:[PLAYER_ITEM]Maybe(VIEW_ENUM),
    is_takeable_item:bit_set[PLAYER_ITEM], 
}

PlayerItemData_InInventory :: struct {
	enum_state:[PLAYER_ITEM]int,
	descriptions:[PLAYER_ITEM][]string,
	index_in_inventory:[PLAYER_ITEM]i8,
}

PlayerItemData :: struct {
    inventory_data:PlayerItemData_InInventory,
    in_view_data:PlayerItemData_InView,
};