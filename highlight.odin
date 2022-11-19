package main

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


HighlightTaskData :: struct {
    surf:^sdl2.Surface,
    h_range:[2]i32,
    working_surroundings:[dynamic][2]i32,
}

when MULTITHREADING {
    highlight_surf_threaded :: proc (ge:^GlobalEverything, item_surf:^sdl2.Surface, highlight_colour:u32, pool:^thread.Pool) {
        tasks : [4]HighlightTaskData
        the_task :: proc (task:thread.Task) {
            data := cast(^HighlightTaskData)task.data
            trace_origin := [2]i32{data.surf.clip_rect.x, data.surf.clip_rect.y}
            mptr := cast([^]u32)data.surf.pixels
        
            for x in -1..<data.surf.w+1 { // MTH: -1..<item_surf.w+1
                iterate_pixel: for y in data.h_range[0]..<data.h_range[1] { // This needs to be sorted. Divided by 4, 
                    test_colour: {
                        switch {
                            case x == -1, y == -1, x == data.surf.w, y == data.surf.h: 
                            break test_colour
                        }
                        idx := point_to_idx(data.surf, {x,y})//4 bytes per pixel
                        center_detected_colour :u32 = detect_colour(mptr[idx], data.surf.format)
                        if !(center_detected_colour == TRANSPARENT_COLOURS[0] || center_detected_colour == TRANSPARENT_COLOURS[1]) do continue iterate_pixel
                    }
                    for _x in -1..=1 do for _y in -1..=1 {
                        _pt := [2]i32{x,y} + {i32(_x), i32(_y)}
                        switch {
                            case _pt.x <= -1, _pt.y <= -1, _pt.x >= data.surf.w, _pt.y >= data.surf.h:
                                continue
                        }
                        _idx := point_to_idx(data.surf, _pt)
                        detected_colour :u32 = detect_colour(mptr[_idx], data.surf.format)
                        if detected_colour == TRANSPARENT_COLOURS[0] || detected_colour == TRANSPARENT_COLOURS[1] do continue
                        append(&data.working_surroundings, trace_origin + {x, y})
                        continue iterate_pixel;
                    }
                }
            }
        }
        
        for x, idx in multithreading_arenas {
            tasks[idx].surf = item_surf
            tasks[idx].working_surroundings = make([dynamic][2]i32)
                                                
            max_quarter := item_surf.h / 4
        
            tasks[idx].h_range[0] = (max_quarter * cast(i32)idx) -1
            tasks[idx].h_range[1] = idx == 3 ? item_surf.h +1 : max_quarter * (cast(i32)idx + 1)
            thread.pool_add_task(pool, multithreading_allocators[idx], the_task, &tasks[idx], idx)
        }
        thread.pool_finish(pool)
        wptr := cast([^]u32)ge.working_surface.pixels
        for x, idx in tasks {
            defer free_all(multithreading_allocators[idx])
            for pt in x.working_surroundings {
                wptr[pt.x+(ge.working_surface.w*pt.y)] = sdl2.MapRGB(ge.working_surface.format,RedOf(highlight_colour),GreenOf(highlight_colour),BlueOf(highlight_colour));
            }
        }
    }
    
}

highlight_surf :: proc (ge:^GlobalEverything, item_surf:^sdl2.Surface, highlight_colour:u32) {
    wptr := cast([^]u32)ge.working_surface.pixels
    mptr := cast([^]u32)item_surf.pixels
    trace_origin := [2]i32{item_surf.clip_rect.x, item_surf.clip_rect.y}
    for x in -1..<item_surf.w+1 { // MTH: -1..<item_surf.w+1
        iterate_pixel: for y in -1..<item_surf.h+1 { // This needs to be sorted. Divided by 4, 
            test_colour: {
                switch {
                    case x == -1, y == -1, x == item_surf.w, y == item_surf.h: 
                    break test_colour
                }
                idx := point_to_idx(item_surf, {x,y})//4 bytes per pixel
                center_detected_colour :u32 = detect_colour(mptr[idx], item_surf.format)
                // fmt.printf("center colour %08X \n", center_detected_colour)
                if !(center_detected_colour == TRANSPARENT_COLOURS[0] || center_detected_colour == TRANSPARENT_COLOURS[1]) do continue iterate_pixel
            }
            for _x in -1..=1 do for _y in -1..=1 {
                _pt := [2]i32{x,y} + {i32(_x), i32(_y)}
                switch {
                    case _pt.x <= -1, _pt.y <= -1, _pt.x >= item_surf.w, _pt.y >= item_surf.h:
                        continue
                }
                _idx := point_to_idx(item_surf, _pt)
                detected_colour :u32 = detect_colour(mptr[_idx], item_surf.format)
                if detected_colour == TRANSPARENT_COLOURS[0] || detected_colour == TRANSPARENT_COLOURS[1] do continue
                __pt := trace_origin + {x, y}
                wptr[__pt.x+(ge.working_surface.w*__pt.y)] = sdl2.MapRGB(ge.working_surface.format,RedOf(highlight_colour),GreenOf(highlight_colour),BlueOf(highlight_colour));
                continue iterate_pixel;
            }
        }
    }
}





