; 24L-598 & 24L-0575 
[org 0x0100]

; bit blaze car race game 

SCR_WIDTH   equ 320
SCR_HEIGHT  equ 200
VIDSEG      equ 0A000h

; road layout
ROADL       equ 60
ROADR       equ 260
BORDERW     equ 8

; spacing
NEARX       equ 40
NEARY       equ 20

; colors
COL_ASPHALT    equ 8
COL_LANEYELLOW equ 14
COL_BORDER     equ 7
COL_LIGHTGREEN equ 10
COL_DARKGREEN  equ 2

; coin size
COINH       equ 12
COIN_HALF   equ COINH/2

; animation constants
SCROLL_SPEED    equ 12             ; even faster road + blue car speed
COIN_SCROLL     equ SCROLL_SPEED   ; coins match road/car speed
SPAWN_INTERVAL  equ 25             ; spawn blue car more often

start:
    mov ax, 0013h
    int 10h

    push cs
    pop ds
    mov ax, VIDSEG
    mov es, ax

    ; lanes
    mov ax, ROADR
    sub ax, ROADL
    inc ax
    mov bl, 3
    div bl
    xor bh, bh
    mov bl, al

    mov ax, ROADL
    mov dl, bl
    xor dh, dh
    add ax, dx
    mov [lane1], ax

    mov ax, ROADL
    mov dl, bl
    xor dh, dh
    add ax, dx
    add ax, dx
    mov [lane2], ax

    ; lane centers (3 lanes)
    mov ax, ROADL
    add ax, [lane1]
    shr ax, 1
    mov [lanec1], ax

    mov ax, [lane1]
    add ax, [lane2]
    shr ax, 1
    mov [lanec2], ax

    mov ax, [lane2]
    add ax, ROADR
    shr ax, 1
    mov [lanec3], ax

    ; safe lane center limits
    mov ax, ROADL
    add ax, BORDERW
    add ax, CARHALFW
    mov [xminc], ax

    mov ax, ROADR
    sub ax, BORDERW
    sub ax, CARHALFW
    mov [xmaxc], ax

    ; clamp lane centers
    mov ax, [lanec1]
    cmp ax, [xminc]
    jae lc1_chk_max
    mov ax, [xminc]
lc1_chk_max:
    cmp ax, [xmaxc]
    jbe lc1_ok
    mov ax, [xmaxc]
lc1_ok:
    mov [lanec1], ax

    mov ax, [lanec2]
    cmp ax, [xminc]
    jae lc2_chk_max
    mov ax, [xminc]
lc2_chk_max:
    cmp ax, [xmaxc]
    jbe lc2_ok
    mov ax, [xmaxc]
lc2_ok:
    mov [lanec2], ax

    mov ax, [lanec3]
    cmp ax, [xminc]
    jae lc3_chk_max
    mov ax, [xminc]
lc3_chk_max:
    cmp ax, [xmaxc]
    jbe lc3_ok
    mov ax, [xmaxc]
lc3_ok:
    mov [lanec3], ax

    ; seed rng with RTC
    mov al, 00h
    out 0x70, al
    jmp seed_delay
seed_delay:
    in  al, 0x71
    mov bl, al
    
    mov al, 02h
    out 0x70, al
    jmp seed_delay2
seed_delay2:
    in  al, 0x71
    mov bh, al
    
    call randstep

    ; center red car between lane1 & lane2
    mov ax, [lane1]
    add ax, [lane2]
    shr ax, 1

    cmp ax, CARHALFW
    ja  start_ok_left
    mov ax, CARHALFW
start_ok_left:
    cmp ax, SCR_WIDTH - CARHALFW
    jbe start_ok_right
    mov ax, SCR_WIDTH - CARHALFW
start_ok_right:
    sub ax, CARHALFW
    mov cx, ax

    ; y = min(160, SCR_HEIGHT - CARH - 1)
    mov ax, SCR_HEIGHT
    sub ax, CARH
    dec ax
    cmp ax, 160
    jae start_use160
    mov dx, ax
    jmp start_y_set
start_use160:
    mov dx, 160
start_y_set:
    mov [redx], cx
    mov [redy], dx

    ; setup blue car columns
    mov ax, ROADL
    add ax, BORDERW
    mov [colstart], ax

    mov ax, ROADR
    sub ax, BORDERW
    mov si, ax
    mov ax, CARW
    dec ax
    sub si, ax
    mov [colend], si

    ; initialize blue car as inactive
    mov word [bluey], 0xFFFF
    mov word [old_bluey], 0xFFFF
    mov word [spawn_timer], SPAWN_INTERVAL

    ; initialize coins (3 coins, one per lane)
    mov word [coin_active],     0
    mov word [coin_active + 2], 0
    mov word [coin_active + 4], 0
    
    ; quick starter coins
    mov ax, [lanec1]
    mov [coin_x], ax
    mov word [coin_y], 20
    mov word [coin_active], 1
    
    mov ax, [lanec2]
    mov [coin_x + 2], ax
    mov word [coin_y + 2], 50
    mov word [coin_active + 2], 1
    
    mov ax, [lanec3]
    mov [coin_x + 4], ax
    mov word [coin_y + 4], 80
    mov word [coin_active + 4], 1

    ; hide cursor
    mov ah, 01h
    mov ch, 32
    int 10h

    ; one-time background
    call draw_background
    
    ; red car is static for now
    mov cx, [redx]
    mov dx, [redy]
    call draw_car_red
    
    ; fuel HUD
    call draw_fuel_hud

; main loop
game_loop:
    ; wipe old blue car
    mov ax, [old_bluey]
    cmp ax, 0xFFFF
    je skip_erase_blue
    mov cx, [old_bluex]
    mov dx, [old_bluey]
    call erase_car
    
skip_erase_blue:
    ; move blue car
    call update_blue_car
    
    ; coins: erase old, move, collision, respawn, draw
    call update_coins
    
    ; blue car draw
    mov ax, [bluey]
    cmp ax, 0xFFFF
    je skip_draw_blue
    mov cx, [bluex]
    mov dx, [bluey]
    call draw_car_blue
    
skip_draw_blue:
    ; spawn animation bookkeeping (car already full-height)
    mov al, [blue_spawn_active]
    cmp al, 0
    je no_spawn_anim_step
    mov ax, [blue_visible_rows]
    add ax, 6
    cmp ax, CARH
    jbe store_vis_rows
    mov ax, CARH
store_vis_rows:
    mov [blue_visible_rows], ax
    cmp ax, CARH
    jne no_spawn_anim_step
    mov byte [blue_spawn_active], 0
no_spawn_anim_step:

    ; remember blue pos
    mov ax, [bluex]
    mov [old_bluex], ax
    mov ax, [bluey]
    mov [old_bluey], ax
    
    ; even faster software delay (smaller loop counts again)
    mov cx, 250           ; fewer outer loops
delay_outer:
    mov dx, 1000          ; fewer inner loops
delay_inner:
    dec dx
    jnz delay_inner
    loop delay_outer
    
    ; ESC to quit
    mov ah, 01h
    int 16h
    jz no_key_pressed

    xor ah, ah
    int 16h
    cmp al, 27
    je exit_to_text

no_key_pressed:
    jmp game_loop

exit_to_text:
    mov ax, 0003h
    int 10h
    mov ax, 4C00h
    int 21h

; erase a 12x12 coin at center (CX, DX)
erase_coin_at:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    
    sub cx, 6
    sub dx, 6
    
    mov bp, dx
    mov si, 12
    
erase_coin_row_loop:
    mov ax, bp
    mov bx, SCR_WIDTH
    mul bx
    mov di, ax
    add di, cx
    
    push cx
    mov cx, 12
    
erase_coin_col_loop:
    push di
    push cx
    
    mov ax, di
    xor dx, dx
    mov bx, SCR_WIDTH
    div bx
    mov bx, dx
    
    cmp bx, ROADL
    jb erase_coin_grass
    cmp bx, ROADR
    ja erase_coin_grass
    
    mov ax, bx
    sub ax, ROADL
    cmp ax, BORDERW
    jb erase_coin_border
    
    mov ax, ROADR
    sub ax, bx
    cmp ax, BORDERW
    jb erase_coin_border
    
    cmp bx, [lane1]
    je erase_coin_lane
    cmp bx, [lane2]
    je erase_coin_lane
    
    mov al, COL_ASPHALT
    jmp erase_coin_write
    
erase_coin_border:
    mov al, COL_BORDER
    jmp erase_coin_write
    
erase_coin_lane:
    test bp, 3
    jnz erase_coin_asphalt
    mov al, COL_LANEYELLOW
    jmp erase_coin_write
    
erase_coin_asphalt:
    mov al, COL_ASPHALT
    jmp erase_coin_write
    
erase_coin_grass:
    mov al, 0
    
erase_coin_write:
    pop cx
    pop di
    mov [es:di], al
    inc di
    loop erase_coin_col_loop
    
    pop cx
    inc bp
    dec si
    jnz erase_coin_row_loop
    
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; coins: erase old, move, collision, respawn, draw
update_coins:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    
    xor si, si
    
coin_update_loop:
    mov bx, si
    shl bx, 1

    ; if active, erase old coin
    mov ax, [coin_active + bx]
    cmp ax, 0
    je skip_erase_this_coin

    mov ax, [coin_x + bx]
    mov cx, ax
    mov ax, [coin_y + bx]
    mov dx, ax
    call erase_coin_at

skip_erase_this_coin:
    mov ax, [coin_active + bx]
    cmp ax, 0
    je coin_maybe_spawn

    ; move coin down at same speed as road/car
    mov ax, [coin_y + bx]
    add ax, COIN_SCROLL
    mov [coin_y + bx], ax
    
    ; past bottom? kill
    cmp ax, SCR_HEIGHT
    jae coin_deactivate
    
    ; collision?
    mov ax, [coin_x + bx]
    mov cx, ax
    mov dx, [coin_y + bx]
    call check_coin_collision
    cmp al, 1
    je coin_deactivate
    
    jmp coin_draw

coin_deactivate:
    mov word [coin_active + bx], 0

coin_maybe_spawn:
    mov ax, [coin_active + bx]
    cmp ax, 0
    jne coin_draw
    call spawn_coin_lane

coin_draw:
    mov ax, [coin_active + bx]
    cmp ax, 0
    je coin_done_one

    mov ax, [coin_x + bx]
    mov dx, [coin_y + bx]
    call draw_coin_circle

coin_done_one:
    inc si
    cmp si, 3
    jb coin_update_loop
    
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; spawn coin in lane SI
spawn_coin_lane:
    push ax
    push bx
    push cx
    push dx
    
    mov bx, si
    shl bx, 1
    
    cmp si, 0
    je set_lane0_x
    cmp si, 1
    je set_lane1_x
    mov ax, [lanec3]
    jmp store_coin_x
    
set_lane1_x:
    mov ax, [lanec2]
    jmp store_coin_x
    
set_lane0_x:
    mov ax, [lanec1]
    
store_coin_x:
    mov [coin_x + bx], ax
    
    ; if blue not active, just random near top
    mov ax, [bluey]
    cmp ax, 0xFFFF
    je spawn_random_y

    ; only tie to blue when same lane
    mov al, [blue_lane]

    cmp si, 0
    je lane0_check
    cmp si, 1
    je lane1_check
    cmp al, 2
    jne spawn_random_y
    jmp spawn_behind_blue

lane1_check:
    cmp al, 1
    jne spawn_random_y
    jmp spawn_behind_blue

lane0_check:
    cmp al, 0
    jne spawn_random_y

spawn_behind_blue:
    ; drop coin a bit behind blue car, but not too low
    mov ax, [blue_bottom]
    add ax, 32

    cmp ax, SCR_HEIGHT - 40
    jbe spawn_y_ok_candidate

    ; if too low, spawn like normal random top
    push bx
    push si
    mov bx, 50
    call getrandom
    add ax, 10
    pop si
    pop bx
    jmp spawn_y_ok_store

spawn_y_ok_candidate:
    cmp ax, SCR_HEIGHT - COIN_HALF
    jbe spawn_y_ok_store
    mov ax, SCR_HEIGHT - COIN_HALF

spawn_y_ok_store:
    mov [coin_y + bx], ax
    jmp activate_coin_now
    
spawn_random_y:
    push bx
    push si
    mov bx, 50
    call getrandom
    add ax, 10
    pop si
    pop bx
    mov [coin_y + bx], ax
    
activate_coin_now:
    mov word [coin_active + bx], 1
    
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; check if coin (CX, DX) hits red car
; AL = 1 if hit, 0 if not
check_coin_collision:
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    
    mov si, [redx]
    mov di, si
    add di, CARW
    
    mov bp, [redy]
    mov bx, bp
    add bx, CARH
    
    push cx
    push dx
    
    sub cx, 6
    mov ax, cx
    add ax, 12
    
    sub dx, 6
    push dx
    add dx, 12
    
    cmp ax, si
    jl no_collision_clean
    
    cmp cx, di
    jg no_collision_clean
    
    cmp dx, bp
    jl no_collision_clean
    
    pop ax
    cmp ax, bx
    jg no_collision_pop
    
    pop dx
    pop cx
    mov al, 1
    jmp collision_done
    
no_collision_clean:
    pop ax
no_collision_pop:
    pop dx
    pop cx
    mov al, 0
    
collision_done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    ret

; draw active coins only (spare)
draw_active_coins:
    push ax
    push bx
    push cx
    push dx
    push si
    
    xor si, si
    
draw_coin_loop_active:
    mov bx, si
    shl bx, 1
    
    mov ax, [coin_active + bx]
    mov [old_coin_active + bx], ax
    
    mov ax, [coin_x + bx]
    mov [old_coin_x + bx], ax
    
    mov ax, [coin_y + bx]
    mov [old_coin_y + bx], ax
    
    mov ax, [coin_active + bx]
    cmp ax, 0
    je skip_this_coin
    
    mov ax, [coin_x + bx]
    mov dx, [coin_y + bx]
    call draw_coin_circle
    
skip_this_coin:
    inc si
    cmp si, 3
    jb draw_coin_loop_active
    
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; erase car by restoring background colors
erase_car:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    mov bp, dx
    mov si, CARH
    
erase_row_loop:
    mov ax, bp
    mov bx, SCR_WIDTH
    mul bx
    mov di, ax
    add di, cx
    
    push cx
    mov cx, CARW
    push si
    mov si, cx
    
erase_col_loop:
    push di
    push cx
    
    mov ax, di
    xor dx, dx
    mov bx, SCR_WIDTH
    div bx
    mov bx, dx
    
    cmp bx, ROADL
    jb erase_grass
    cmp bx, ROADR
    ja erase_grass
    
    mov ax, bx
    sub ax, ROADL
    cmp ax, BORDERW
    jb erase_border
    
    mov ax, ROADR
    sub ax, bx
    cmp ax, BORDERW
    jb erase_border
    
    cmp bx, [lane1]
    je erase_lane_mark
    cmp bx, [lane2]
    je erase_lane_mark
    
    mov al, COL_ASPHALT
    jmp erase_write
    
erase_border:
    mov al, COL_BORDER
    jmp erase_write
    
erase_lane_mark:
    test bp, 3
    jnz erase_asphalt_lane
    mov al, COL_LANEYELLOW
    jmp erase_write
    
erase_asphalt_lane:
    mov al, COL_ASPHALT
    jmp erase_write
    
erase_grass:
    mov al, 0
    
erase_write:
    pop cx
    pop di
    mov [es:di], al
    inc di
    loop erase_col_loop
    
    pop si
    pop cx
    inc bp
    dec si
    jnz erase_row_loop
    
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; move blue car and handle spawn timer
update_blue_car:
    push ax
    push bx
    push cx
    push dx
    push si
    
    mov ax, [bluey]
    cmp ax, 0xFFFF
    je check_spawn
    
    add ax, SCROLL_SPEED
    mov [bluey], ax
    
    add ax, CARH
    mov [blue_bottom], ax
    
    mov dx, [bluey]
    cmp dx, SCR_HEIGHT
    jae deactivate_blue
    jmp update_done
    
deactivate_blue:
    mov word [bluey], 0xFFFF
    mov byte [blue_spawn_active], 0
    jmp check_spawn
    
check_spawn:
    dec word [spawn_timer]
    jnz update_done
    
    mov al, 00h
    out 0x70, al
    nop
    in  al, 0x71
    and al, 0x0F
    add al, SPAWN_INTERVAL
    xor ah, ah
    mov [spawn_timer], ax
    
    call spawn_blue_car
    
update_done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; spawn a new blue car at top of lane, fully visible instantly
spawn_blue_car:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    
    mov bx, 3
    call getrandom
    mov si, ax
    mov di, 3
    
spawn_pick_lane:
    cmp si, 0
    je spawn_use_c1
    cmp si, 1
    je spawn_use_c2
    mov ax, [lanec3]
    jmp spawn_have_center
    
spawn_use_c2:
    mov ax, [lanec2]
    add ax, 6
    jmp spawn_have_center
    
spawn_use_c1:
    mov ax, [lanec1]
    
spawn_have_center:
    sub ax, CARHALFW
    mov cx, ax

    cmp ax, [colstart]
    jae spawn_chk_right
    mov cx, [colstart]
    jmp spawn_x_ready
    
spawn_chk_right:
    cmp ax, [colend]
    jbe spawn_x_ready
    mov cx, [colend]
    
spawn_x_ready:
    mov ax, cx
    add ax, CARHALFW
    mov dx, [redx]
    add dx, CARHALFW
    sub ax, dx
    jns spawn_abs_ok
    neg ax
    
spawn_abs_ok:
    cmp ax, NEARX
    jae spawn_x_far
    dec di
    jz spawn_force
    inc si
    cmp si, 3
    jb spawn_pick_lane
    xor si, si
    jmp spawn_pick_lane
    
spawn_force:
spawn_x_far:
    ; spawn at very top of lane, y=0
    mov [blue_lane], si
    mov dx, 0
    mov [bluey], dx
    mov [bluex], cx
    mov ax, dx
    add ax, CARH
    mov [blue_bottom], ax

    ; show full car instantly (no slow reveal)
    mov byte [blue_spawn_active], 1
    mov word [blue_visible_rows], CARH

    ; kill + erase coin in same lane so car doesn't appear on top of it
    xor ah, ah
    mov al, [blue_lane]
    mov bx, ax
    shl bx, 1

    mov ax, [coin_active + bx]
    cmp ax, 0
    je no_lane_coin_to_erase

    mov cx, [coin_x + bx]
    mov dx, [coin_y + bx]
    call erase_coin_at

no_lane_coin_to_erase:
    mov word [coin_active + bx], 0

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; background drawing (one time)
draw_background:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    xor di, di
    xor bx, bx
    xor bp, bp
    
bg_row_loop:
    mov cx, SCR_WIDTH
    xor si, si
    
bg_col_loop:
    mov ax, si
    cmp ax, ROADL
    jb bg_outside_grass
    cmp ax, ROADR
    ja bg_outside_grass

    mov ax, si
    sub ax, ROADL
    cmp ax, BORDERW
    jb bg_paint_border

    mov ax, ROADR
    sub ax, si
    cmp ax, BORDERW
    jb bg_paint_border

    mov al, COL_ASPHALT

    mov dx, si
    cmp dx, [lane1]
    je bg_maybe_dash
    cmp dx, [lane2]
    je bg_maybe_dash
    jmp bg_write_pixel
    
bg_paint_border:
    mov al, COL_BORDER
    jmp bg_write_pixel
    
bg_maybe_dash:
    test bp, 3
    jnz bg_write_pixel
    mov al, COL_LANEYELLOW
    jmp bg_write_pixel
    
bg_outside_grass:
    mov al, 0
    
bg_write_pixel:
    mov [es:di], al
    inc di
    inc si
    loop bg_col_loop
    inc bp

    cmp di, SCR_WIDTH*SCR_HEIGHT
    jae bg_done
    jmp bg_row_loop

bg_done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; draw red car
draw_car_red:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov ax, dx
    mov bx, SCR_WIDTH
    mul bx
    mov di, ax
    add di, cx

    mov si, car_sprite
    mov cx, CARH
    
draw_red_row:
    push cx
    push di
    mov cx, CARW
    
draw_red_col:
    lodsb
    or al, al
    jz draw_red_skip
    mov [es:di], al
    
draw_red_skip:
    inc di
    loop draw_red_col
    pop di
    add di, SCR_WIDTH
    pop cx
    loop draw_red_row

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; draw blue car with clipping and back-to-front spawn logic
draw_car_blue:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    mov bp, CARH

    mov al, [blue_spawn_active]
    cmp al, 0
    je skip_spawn_h_override
    mov bp, [blue_visible_rows]
skip_spawn_h_override:

    mov ax, dx
    add ax, bp
    cmp ax, SCR_HEIGHT
    jbe blue_all_visible
    
    mov ax, SCR_HEIGHT
    sub ax, dx
    cmp ax, 0
    jle blue_draw_done
    mov bp, ax

blue_all_visible:
    mov ax, dx
    mov bx, SCR_WIDTH
    mul bx
    mov di, ax
    add di, cx

    mov si, car_blue_sprite

    mov al, [blue_spawn_active]
    cmp al, 0
    je no_spawn_row_offset
    mov ax, CARH
    sub ax, bp
    mov bx, CARW
    mul bx
    add si, ax
no_spawn_row_offset:

    mov cx, bp
    
draw_blue_row:
    push cx
    push di
    mov cx, CARW
    
draw_blue_col:
    lodsb
    or  al, al
    jz  draw_blue_skip
    cmp al, 12
    jne chk_blue_red
    mov al, 9
    jmp recolor_store
    
chk_blue_red:
    cmp al, 4
    jne chk_blue_dark
    mov al, 1
    jmp recolor_store
    
chk_blue_dark:
    cmp al, 3
    jne recolor_store
    mov al, 1
    
recolor_store:
    mov [es:di], al
    
draw_blue_skip:
    inc di
    loop draw_blue_col
    pop di
    add di, SCR_WIDTH
    pop cx
    loop draw_blue_row

blue_draw_done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; coin circle
draw_coin_circle:
    mov [coin_base_x], ax
    mov [coin_base_y], dx
    sub word [coin_base_x], 6
    sub word [coin_base_y], 6

    push ax
    push bx
    push cx
    push dx
    push si
    push di

    xor si, si
    
coin_row_loop:
    mov ax, [coin_base_y]
    add ax, si
    mov cx, SCR_WIDTH
    mul cx
    mov di, ax
    mov ax, [coin_base_x]
    add di, ax

    mov bx, si
    shl bx, 1
    mov dx, [coin_mask + bx]

    mov cx, 12
    
coin_col_loop:
    test dx, 1
    jz coin_skip_px
    mov al, COL_LANEYELLOW
    mov [es:di], al
    
coin_skip_px:
    inc di
    shr dx, 1
    loop coin_col_loop

    inc si
    cmp si, 12
    jb coin_row_loop

    ; tiny shadow
    mov ax, [coin_base_y]
    add ax, 8
    mov cx, SCR_WIDTH
    mul cx
    mov di, ax
    mov ax, [coin_base_x]
    add di, ax
    add di, 8

    mov cx, 3
    
shadow_row_loop:
    push cx
    mov cx, 3
    
shadow_col_loop:
    mov al, 0
    mov [es:di], al
    inc di
    loop shadow_col_loop
    add di, SCR_WIDTH
    sub di, 3
    pop cx
    dec cx
    jnz shadow_row_loop

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; fuel HUD
draw_fuel_hud:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov ah, 02h
    xor bh, bh
    mov dh, 22
    mov dl, 1
    int 10h

    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Eh

    mov al, 'F'
    int 10h
    mov al, 'U'
    int 10h
    mov al, 'E'
    int 10h
    mov al, 'L'
    int 10h

    mov ax, VIDSEG
    mov es, ax

    mov bp, 184
    mov si, 10
    mov ax, bp
    mov bx, SCR_WIDTH
    mul bx
    add ax, si
    mov di, ax

    mov bx, 6
    
fuel_row_loop:
    push bx
    mov cx, 40
    
fuel_col_loop:
    mov al, 12
    mov [es:di], al
    inc di
    loop fuel_col_loop
    add di, SCR_WIDTH
    sub di, 40
    pop bx
    dec bx
    jnz fuel_row_loop

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; RNG
randstep:
    mov ax, bx
    shl bx, 5
    add bx, ax
    add bx, 7
    mov ax, bx
    ret

getrandom:
    push dx
    push cx
    cmp bx, 1
    ja gr_mod_ok
    xor ax, ax
    jmp gr_exit
    
gr_mod_ok:
    mov ah, 00h
    int 1Ah
    mov ax, dx
    xor dx, dx
    div bx
    mov ax, dx
    
gr_exit:
    pop cx
    pop dx
    ret

; sprites
%include "car_red.inc"
car_sprite_end:
car_blue_sprite     equ car_sprite
car_blue_sprite_end equ car_sprite_end

sprite_bytes equ car_sprite_end - car_sprite
%assign _carw 0
%macro tryw 1
%if _carw = 0
 %if (sprite_bytes %% %1) = 0
  %assign _carw %1
 %endif
%endif
%endmacro
tryw 45
tryw 60
tryw 56
tryw 50
tryw 48
tryw 45
tryw 40
tryw 32
%if _carw = 0
 %error "could not infer CARW"
%endif
CARW     equ _carw
CARH     equ sprite_bytes / CARW
CARHALFW equ (CARW/2)

; data
lane1      dw 0
lane2      dw 0
redx       dw 0
redy       dw 0
colspan    dw 0
rowspan    dw 0
colstart   dw 0
colend     dw 0
rowmin     dw 0
rowmax     dw 0
lanec1     dw 0
lanec2     dw 0
lanec3     dw 0
xminc      dw 0
xmaxc      dw 0

blue_lane         db 0
bluex             dw 0
bluey             dw 0
blue_bottom       dw 0
old_bluex         dw 0
old_bluey         dw 0
blue_spawn_active db 0       ; 1 while spawn phase
blue_visible_rows dw 0       ; visible rows (now starts at CARH)

coin_base_x  dw 0
coin_base_y  dw 0

spawn_timer  dw SPAWN_INTERVAL

; coin state
coin_active dw 0, 0, 0
coin_x     dw 0, 0, 0
coin_y     dw 0, 0, 0

; old coin state (spare)
old_coin_active dw 0, 0, 0
old_coin_x      dw 0, 0, 0
old_coin_y      dw 0, 0, 0

coin_blue_offsets dw 16, 32, 48

coin_mask dw 000000000000b, \
             000111111000b, \
             001111111100b, \
             011111111110b, \
             011111111110b, \
             011111111110b, \
             011111111110b, \
             011111111110b, \
             011111111110b, \
             001111111100b, \
             000111111000b, \
             000000000000b
