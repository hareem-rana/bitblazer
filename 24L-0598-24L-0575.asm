;24L-0598 & 24L-0575
[org 0x0100]

;bit blazer race game

SCR_WIDTH   equ 320
SCR_HEIGHT  equ 200
VIDSEG      equ 0A000h

ROADL       equ 60
ROADR       equ 260
BORDERW     equ 8

NEARX       equ 40
NEARY       equ 20

COL_ASPHALT    equ 8
COL_LANEYELLOW equ 14
COL_BORDER     equ 7

COINH       equ 12
COIN_HALF   equ COINH/2

SCROLL_SPEED       equ 12
COIN_SCROLL        equ 12
MIN_SPAWN_DELAY    equ 12
MAX_SPAWN_DELAY    equ 30
COIN_RESPAWN_DELAY equ 40

MAX_BLUE_CARS equ 5


; Start game
start:
    mov ax, 13h
    int 10h

    push cs
    pop ds
    mov ax, VIDSEG
    mov es, ax

    ; lane width = (ROADR - ROADL + 1) / 3
    mov ax, ROADR
    sub ax, ROADL
    inc ax
    mov bl, 3
    div bl
    xor bh, bh
    mov bl, al

    ; lane1 = ROADL + laneWidth
    mov ax, ROADL
    mov dl, bl
    xor dh, dh
    add ax, dx
    mov [lane1], ax

    ; lane2 = ROADL + 2*laneWidth
    mov ax, ROADL
    mov dl, bl
    xor dh, dh
    add ax, dx
    add ax, dx
    mov [lane2], ax

    ; calculate lane centers
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

    ; safe x min / max for centers
    mov ax, ROADL
    add ax, BORDERW
    add ax, CARHALFW
    mov [xminc], ax

    mov ax, ROADR
    sub ax, BORDERW
    sub ax, CARHALFW
    mov [xmaxc], ax

    ; clamp lanec1
    mov ax, [lanec1]
    cmp ax, [xminc]
    jae lane1_min_ok
    mov ax, [xminc]
lane1_min_ok:
    cmp ax, [xmaxc]
    jbe lane1_max_ok
    mov ax, [xmaxc]
lane1_max_ok:
    mov [lanec1], ax

    ; clamp lanec2
    mov ax, [lanec2]
    cmp ax, [xminc]
    jae lane2_min_ok
    mov ax, [xminc]
lane2_min_ok:
    cmp ax, [xmaxc]
    jbe lane2_max_ok
    mov ax, [xmaxc]
lane2_max_ok:
    mov [lanec2], ax

    ; clamp lanec3
    mov ax, [lanec3]
    cmp ax, [xminc]
    jae lane3_min_ok
    mov ax, [xminc]
lane3_min_ok:
    cmp ax, [xmaxc]
    jbe lane3_max_ok
    mov ax, [xmaxc]
lane3_max_ok:
    mov [lanec3], ax

    ; center red car horizontally between lane1 and lane2
    mov ax, [lane1]
    add ax, [lane2]
    shr ax, 1

    cmp ax, CARHALFW
    ja near red_left_ok
    mov ax, CARHALFW
red_left_ok:
    cmp ax, SCR_WIDTH - CARHALFW
    jbe near red_right_ok
    mov ax, SCR_WIDTH - CARHALFW
red_right_ok:
    sub ax, CARHALFW
    mov [redx], ax

    ; set red car Y
    mov ax, SCR_HEIGHT
    sub ax, CARH
    dec ax
    cmp ax, 160
    jae set_redy
    mov dx, ax
    jmp near set_redy_done
set_redy:
    mov dx, 160
set_redy_done:
    mov [redy], dx

    mov byte [red_lane], 1

    ; column safe range for blue cars
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

    ; initialize blue cars
    call init_blue_cars

    ; random spawn timer
    mov bx, MAX_SPAWN_DELAY - MIN_SPAWN_DELAY + 1
    call getrandom
    add ax, MIN_SPAWN_DELAY
    mov [spawn_timer], ax

    ; setup coins initially
    mov word [coin_active], 0
    mov word [coin_active+2], 0
    mov word [coin_active+4], 0

    mov ax, [lanec2]
    mov [coin_x+2], ax
    mov word [coin_y+2], 40
    mov word [coin_active+2], 1

    mov word [coin_spawn_timer], COIN_RESPAWN_DELAY
    mov word [game_over_flag], 0
    mov word [coin_count], 0
    mov word [fuel_value], 12

    ; hide cursor
    mov ah, 01h
    mov ch, 32
    int 10h

    call show_start_screen
    call draw_background

    ; force spawn a blue car at start screen
    mov si, 0             ; use blue car slot 0
    call spawn_blue_car   ; create 1 proper blue car

    ; need to draw car for static screen and we need to make sure its visible on the road
    mov si,0
    call get_blue_car_ptr      ; BX -> car0 struct
    mov word [bx + 4], 20      ; y = 20 (visible on road)
    mov ax, 20
    add ax, CARH
    mov [bx + 6], ax           ; bottom = y + height

    xor si, si
    call get_blue_car_ptr
    mov cx, [bx+2]
    mov dx, [bx+4]
    call draw_car_blue

    mov cx, [redx]
    mov dx, [redy]
    call draw_car_red

    call draw_fuel_hud
    call draw_coin_hud
    call draw_fuel_text
    call show_press_to_start_overlay


game_loop:

    call erase_all_blue_cars
    call update_all_blue_cars
    call update_coins
    call draw_all_blue_cars

    mov cx, [redx]
    mov dx, [redy]
    call draw_car_red

    mov ah, 01h
    int 16h
    jz near no_key

    xor ah, ah
    int 16h

    cmp al, 27
    je key_escape

    cmp al, 0
    jne near no_key

    cmp ah, 4Bh
    je key_move_left

    cmp ah, 4Dh
    je key_move_right
	
    cmp ah, 48h
    je key_move_up

    cmp ah, 50h
    je key_move_down

    jmp no_key

key_escape:
    call confirm_exit
    cmp al, 1
    je near exit_to_dos
    call redraw_full_scene
    jmp after_keys

key_move_left:
    mov cx, [redx]
    mov dx, [redy]
    call erase_car
    call move_red_left
    mov cx, [redx]
    mov dx, [redy]
    call draw_car_red
    jmp after_keys

key_move_right:
    mov cx, [redx]
    mov dx, [redy]
    call erase_car
    call move_red_right
    mov cx, [redx]
    mov dx, [redy]
    call draw_car_red
    jmp after_keys

key_move_up:
    mov cx, [redx]
    mov dx, [redy]
    call erase_car
    call move_red_up
    mov cx, [redx]
    mov dx, [redy]
    call draw_car_red
    jmp after_keys

key_move_down:
    mov cx, [redx]
    mov dx, [redy]
    call erase_car
    call move_red_down
    mov cx, [redx]
    mov dx, [redy]
    call draw_car_red
    jmp after_keys

move_red_up:
    push ax

    mov ax, [redy]
    cmp ax, 20          ; top limit
    jle mru_no_move
    sub ax, 20          ; move up 20 pixels
    mov [redy], ax

mru_no_move:
    pop ax
    ret

move_red_down:
    push ax

    mov ax, [redy]
    add ax, 20          ; move down 20 pixels
    cmp ax, SCR_HEIGHT - CARH
    jge mrd_no_move
    mov [redy], ax
    jmp mrd_done

mrd_no_move:
    ; clamp to bottom
    mov ax, SCR_HEIGHT - CARH
    mov [redy], ax

mrd_done:
    pop ax
    ret

no_key:

after_keys:
    call check_blue_collisions
    cmp word [game_over_flag], 0
    jne game_over_mode

    mov cx, 250
delay_outer:
    mov dx, 1000
delay_inner:
    dec dx
    jnz delay_inner
    loop delay_outer

    jmp game_loop

game_over_mode:
    call game_over_screen
    mov ah, 0
    int 16h
    jmp near exit_to_dos

exit_to_dos:
    mov ax, 3
    int 10h
    mov ax, 4C00h
    int 21h
; initialize all blue cars as inactive
init_blue_cars:
    push ax
    push bx
    push cx
    push si
    
    xor si, si
init_blue_loop:
    call get_blue_car_ptr
    mov word [bx], 0          ; active = 0
    mov word [bx + 2], 0      ; x
    mov word [bx + 4], 0FFFFh ; y = offscreen
    mov word [bx + 6], 0      ; bottom
    mov byte [bx + 8], 0      ; lane
    mov word [bx + 10], 0      ; old_x
    mov word [bx + 12], 0FFFFh ; old_y
    
    inc si
    cmp si, MAX_BLUE_CARS
    jb init_blue_loop
    
    pop si
    pop cx
    pop bx
    pop ax
    ret


; get pointer to blue car structure at index SI
; returns BX = pointer to structure
get_blue_car_ptr:
    push ax
    mov bx, si
    mov ax, 14               ; 14 bytes per car
    mul bx
    mov bx, blue_cars
    add bx, ax
    pop ax
    ret


; erase all active blue cars using old positions
erase_all_blue_cars:
    push ax
    push bx
    push cx
    push dx
    push si
    
    xor si, si
erase_all_loop:
    call get_blue_car_ptr
    
    mov ax, [bx + 12]         ; old_y
    cmp ax, 0FFFFh
    je erase_skip
    cmp ax, SCR_HEIGHT
    jge erase_skip
    
    mov cx, [bx + 10]          ; old_x
    mov dx, [bx + 12]         ; old_y
    call erase_car
    
erase_skip:
    inc si
    cmp si, MAX_BLUE_CARS
    jb erase_all_loop
    
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; draw all active blue cars
draw_all_blue_cars:
    push ax
    push bx
    push cx
    push dx
    push si
    
    xor si, si
draw_blue_all_loop:
    call get_blue_car_ptr
    
    mov ax, [bx]
    cmp ax, 0
    je draw_blue_skip_car
    
    mov ax, [bx + 4]          ; y
    cmp ax, 0FFFFh
    je draw_blue_skip_car
    cmp ax, SCR_HEIGHT
    jge draw_blue_skip_car
    
    mov cx, [bx + 2]          ; x
    mov dx, [bx + 4]          ; y
    call draw_car_blue
    
draw_blue_skip_car:
    inc si
    cmp si, MAX_BLUE_CARS
    jb draw_blue_all_loop
    
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; update all blue cars (movement and spawning)
update_all_blue_cars:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    
    xor si, si
update_blue_all_loop:
    call get_blue_car_ptr
    
    mov ax, [bx]
    cmp ax, 0
    je blue_try_spawn
    
    ; save old position
    mov ax, [bx + 2]
    mov [bx + 10], ax
    mov ax, [bx + 4]
    mov [bx + 12], ax
    
    ; move car down
    mov ax, [bx + 4]
    add ax, SCROLL_SPEED
    mov [bx + 4], ax
    
    ; update bottom
    mov dx, ax
    add dx, CARH
    mov [bx + 6], dx
    
    ; deactivate if fully off screen
    cmp ax, SCR_HEIGHT
    jl update_blue_next
    
    mov word [bx], 0
    mov word [bx + 4], 0FFFFh
    jmp near update_blue_next
    
blue_try_spawn:
    ; check spawn timer only once per frame (but allow car spawning regardless of SI)
	dec word [spawn_timer]
	jnz update_blue_next

	; reset spawn timer
	push bx
	mov bx, MAX_SPAWN_DELAY - MIN_SPAWN_DELAY + 1
	call getrandom
	add ax, MIN_SPAWN_DELAY
	mov [spawn_timer], ax
	pop bx

	; find first inactive car
	call find_inactive_car
	cmp si, 0FFFFh
	je update_blue_next

	call spawn_blue_car

update_blue_next:
    inc si
    cmp si, MAX_BLUE_CARS
    jb update_blue_all_loop
    
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; find first inactive blue car
; returns SI index or 0FFFFh if all active
find_inactive_car:
    push ax
    push bx
    push cx
    
    xor si, si
find_inactive_loop:
    call get_blue_car_ptr
    mov ax, [bx]
    cmp ax, 0
    je find_inactive_found
    
    inc si
    cmp si, MAX_BLUE_CARS
    jb find_inactive_loop
    
    mov si, 0FFFFh
    jmp find_inactive_done
    
find_inactive_found:
find_inactive_done:
    pop cx
    pop bx
    pop ax
    ret


; spawn a blue car at index SI (array version)
spawn_blue_car:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    ; get pointer to this car slot (index in SI)
    call get_blue_car_ptr
    mov bp, bx              ; save pointer for this car slot in BP

    ; choose random lane 0..2
    mov bx, 3
    call getrandom          ; ax = 0..2
    mov di, ax              ; lane index
    mov [bp + 8], di        ; store lane in this car slot
    mov [spawn_lane], di    ; store for overlap checks

    ; convert lane -> lane center
    cmp di, 0
    je sbc_lane1
    cmp di, 1
    je sbc_lane2
    mov ax, [lanec3]
    jmp sbc_lane_ok

sbc_lane2:
    mov ax, [lanec2]
    jmp sbc_lane_ok

sbc_lane1:
    mov ax, [lanec1]

sbc_lane_ok:
    ; convert center → left side
    sub ax, CARHALFW
    mov cx, ax

    ; clamp X so car never goes off-road
    cmp cx, [colstart]
    jae sbc_chk_right
    mov cx, [colstart]
    jmp sbc_x_ok

sbc_chk_right:
    cmp cx, [colend]
    jbe sbc_x_ok
    mov cx, [colend]

sbc_x_ok:

    ; ANTI-OVERLAP CHECK

   xor di, di
sbc_overlap_loop:
    cmp di, MAX_BLUE_CARS
    je sbc_no_overlap

    mov si, di
    call get_blue_car_ptr   ; BX = pointer to existing car

    cmp word [bx], 1
    jne sbc_next

    ; same lane?
    mov al, [bx + 8]
    cmp al, [spawn_lane]
    jne sbc_next

    ; existing_y in range [-CARH .. CARH+20] ?
    mov ax, [bx + 4]

    ; if existing_y < -CARH → too high, ignore
    cmp ax, -CARH
    jl sbc_next

    ; if existing_y > (CARH+20) → far enough, ignore
    cmp ax, CARH + 20
    jg sbc_next

    ; otherwise TOO CLOSE, block spawn
    jmp near sbc_abort_spawn

sbc_next:
    inc di
    jmp sbc_overlap_loop

sbc_no_overlap:
    ; SAFE TO ACTIVATE THIS CAR SLOT
    mov bx, bp                ; restore pointer to chosen slot

    mov word [bx], 1          ; active = 1
    mov [bx + 2], cx          ; x position
    mov ax, -CARH
    mov [bx + 4], ax          ; y position
    add ax, CARH
    mov [bx + 6], ax          ; bottom Y

    jmp near sbc_done

; overlap found -> do not spawn anything this frame
sbc_abort_spawn:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

sbc_done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; erase a 12x12 coin at center CX,DX
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
    mov [coin_base_x], cx
    mov [coin_base_y], dx

    xor si, si

erase_coin_row_loop:
    mov ax, [coin_base_y]
    add ax, si
    mov bp, ax

    mov bx, SCR_WIDTH
    mul bx
    mov di, ax
    mov ax, [coin_base_x]
    add di, ax

    mov bx, [coin_base_x]
    mov cx, 12

erase_coin_col_loop:
    ; check overlap with red car
    mov ax, [redx]
    cmp bx, ax
    jb erase_not_red
    mov dx, ax
    add dx, CARW
    cmp bx, dx
    jae erase_not_red

    mov ax, bp
    cmp ax, [redy]
    jb erase_not_red
    mov dx, [redy]
    add dx, CARH
    cmp ax, dx
    jae erase_not_red

    mov ax, bp
    sub ax, [redy]
    mov dx, CARW
    mul dx
    mov dx, bx
    sub dx, [redx]
    add ax, dx
    push si
    mov si, car_sprite
    add si, ax
    mov al, [si]
    pop si
    or  al, al
    jz erase_not_red
    jmp erase_write_pixel

erase_not_red:
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
    je erase_lane
    cmp bx, [lane2]
    je erase_lane

    mov al, COL_ASPHALT
    jmp erase_write_pixel

erase_border:
    mov al, COL_BORDER
    jmp erase_write_pixel

erase_lane:
    test bp, 3
    jnz erase_lane_asphalt
    mov al, COL_LANEYELLOW
    jmp erase_write_pixel

erase_lane_asphalt:
    mov al, COL_ASPHALT
    jmp erase_write_pixel

erase_grass:
    mov al, 0

erase_write_pixel:
    mov [es:di], al
    inc di
    inc bx
    dec cx
    jnz erase_coin_col_loop

    inc si
    cmp si, 12
    jb erase_coin_row_loop
    
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; coins: erase, move, collision, respawn, draw
update_coins:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    cmp word [coin_spawn_timer], 0
    jle coin_do_spawn
    dec word [coin_spawn_timer]
    jmp coin_after_spawn

coin_do_spawn:
    call spawn_coin_once
    mov word [coin_spawn_timer], COIN_RESPAWN_DELAY

coin_after_spawn:
    xor si, si

coin_loop:
    mov bx, si
    shl bx, 1

    mov ax, [coin_active + bx]
    cmp ax, 0
    je coin_next

    mov ax, [coin_x + bx]
    mov cx, ax
    mov ax, [coin_y + bx]
    mov dx, ax
    call erase_coin_at

    mov ax, [coin_y + bx]
    add ax, COIN_SCROLL
    mov [coin_y + bx], ax

    cmp ax, SCR_HEIGHT
    jae coin_deactivate

    mov ax, [coin_x + bx]
    mov cx, ax
    mov dx, [coin_y + bx]
    call check_coin_collision
    cmp al, 1
    jne coin_no_hit

    mov ax, [coin_x + bx]
    mov cx, ax
    mov dx, [coin_y + bx]
    call erase_coin_at

    mov cx, [redx]
    mov dx, [redy]
    call draw_car_red

    inc word [coin_count]
    call draw_coin_hud
    jmp coin_deactivate

coin_no_hit:
    mov ax, [coin_x + bx]
    mov dx, [coin_y + bx]
    call draw_coin_circle
    jmp coin_after_coin

coin_deactivate:
    mov word [coin_active + bx], 0

coin_after_coin:
coin_next:
    inc si
    cmp si, 3
    jb coin_loop

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; choose a random inactive lane and spawn one coin
spawn_coin_once:
    push ax
    push bx
    push cx
    push dx
    push si

    mov si, 0
    mov cx, 3

spawn_coin_check_inactive:
    mov bx, si
    shl bx, 1
    mov ax, [coin_active + bx]
    cmp ax, 0
    je spawn_coin_found_inactive
    inc si
    loop spawn_coin_check_inactive

    jmp near spawn_coin_done

spawn_coin_found_inactive:
    mov cx, 3

spawn_coin_try_lane:
    mov bx, 3
    call getrandom       ; ax = 0..2
    mov si, ax

    mov bx, si
    shl bx, 1
    mov ax, [coin_active + bx]
    cmp ax, 0
    je spawn_coin_do
    loop spawn_coin_try_lane
    jmp near spawn_coin_done

spawn_coin_do:
    call spawn_coin_lane

spawn_coin_done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; spawn coin in lane SI, avoid overlap with blue cars if possible
spawn_coin_lane:
    push ax
    push bx
    push cx
    push dx
    push di

    mov bx, si
    shl bx, 1

    cmp si, 0
    je spawn_coin_lane0
    cmp si, 1
    je spawn_coin_lane1
    mov ax, [lanec3]
    jmp spawn_coin_store_x

spawn_coin_lane1:
    mov ax, [lanec2]
    jmp spawn_coin_store_x

spawn_coin_lane0:
    mov ax, [lanec1]

spawn_coin_store_x:
    mov [coin_x + bx], ax

    ; try to position relative to any blue car in this lane
    push si
    xor di, di
spawn_coin_check_blue:
    push bx
    mov si, di
    call get_blue_car_ptr

    mov ax, [bx]
    cmp ax, 0
    je spawn_coin_next_blue

    mov al, [bx + 8]
    pop bx
    push bx
    cmp al, [si]         ; compare lane index
    jne spawn_coin_next_blue

    mov ax, [bx + 6]     ; bottom of blue car
    add ax, 32

    cmp ax, SCR_HEIGHT - 40
    jbe spawn_coin_candidate

    push bx
    mov bx, 50
    call getrandom
    add ax, 10
    pop bx
    jmp spawn_coin_store_y

spawn_coin_candidate:
    cmp ax, SCR_HEIGHT - COIN_HALF
    jbe spawn_coin_store_y
    mov ax, SCR_HEIGHT - COIN_HALF

spawn_coin_store_y:
    pop bx
    pop si
    mov [coin_y + bx], ax
    jmp spawn_coin_activate

spawn_coin_next_blue:
    pop bx
    inc di
    cmp di, MAX_BLUE_CARS
    jb spawn_coin_check_blue

    pop si

    push bx
    mov bx, 50
    call getrandom
    add ax, 10
    pop bx
    mov [coin_y + bx], ax

spawn_coin_activate:
    mov word [coin_active + bx], 1

    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; check if coin at CX,DX collides with red car
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
    jl coin_no_collision_clean
    
    cmp cx, di
    jg coin_no_collision_clean
    
    cmp dx, bp
    jl coin_no_collision_clean
    
    pop ax
    cmp ax, bx
    jg coin_no_collision_pop
    
    pop dx
    pop cx
    mov al, 1
    jmp coin_collision_done
    
coin_no_collision_clean:
    pop ax
coin_no_collision_pop:
    pop dx
    pop cx
    mov al, 0
    
coin_collision_done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    ret


; erase any car (red or blue) at CX,DX using road background
erase_car:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    mov ax, dx
    cmp ax, SCR_HEIGHT
    jl erase_car_check_top
    jmp erase_car_done

erase_car_check_top:
    mov ax, dx
    add ax, CARH
    cmp ax, 0
    jg erase_car_compute
    jmp erase_car_done

erase_car_compute:
    mov bp, dx
    cmp bp, 0
    jge erase_car_y_start_ok
    xor bp, bp
erase_car_y_start_ok:
    mov ax, dx
    add ax, CARH
    cmp ax, SCR_HEIGHT
    jle erase_car_y_end_ok
    mov ax, SCR_HEIGHT
erase_car_y_end_ok:
    sub ax, bp
    mov si, ax

    mov ax, bp
    mov bx, SCR_WIDTH
    mul bx
    mov di, ax
    add di, cx

erase_car_row_loop:
    cmp si, 0
    jle erase_car_done

    push cx
    push dx
    push si

    mov cx, CARW

erase_car_col_loop:
    push di
    push cx

    mov ax, di
    xor dx, dx
    mov bx, SCR_WIDTH
    div bx
    mov bx, dx

    cmp bx, ROADL
    jb erase_car_grass
    cmp bx, ROADR
    ja erase_car_grass

    mov ax, bx
    sub ax, ROADL
    cmp ax, BORDERW
    jb erase_car_border

    mov ax, ROADR
    sub ax, bx
    cmp ax, BORDERW
    jb erase_car_border

    cmp bx, [lane1]
    je erase_car_lane
    cmp bx, [lane2]
    je erase_car_lane

    mov al, COL_ASPHALT
    jmp erase_car_write

erase_car_border:
    mov al, COL_BORDER
    jmp erase_car_write

erase_car_lane:
    test bp, 3
    jnz erase_car_lane_asphalt
    mov al, COL_LANEYELLOW
    jmp erase_car_write

erase_car_lane_asphalt:
    mov al, COL_ASPHALT
    jmp erase_car_write

erase_car_grass:
    mov al, 0

erase_car_write:
    pop cx
    pop di
    mov [es:di], al
    inc di
    loop erase_car_col_loop

    pop si
    pop dx
    pop cx

    inc bp
    dec si
    jz erase_car_done

    mov ax, SCR_WIDTH
    sub ax, CARW
    add di, ax
    jmp erase_car_row_loop

erase_car_done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; move red car left between lanes
move_red_left:
    push ax

    mov al, [red_lane]
    cmp al, 0
    jbe move_red_left_no_dec
    dec al
    mov [red_lane], al
move_red_left_no_dec:
    xor ah, ah

    cmp ax, 0
    je move_red_left_lane1
    cmp ax, 1
    je move_red_left_lane2
    mov ax, [lanec3]
    jmp move_red_left_store

move_red_left_lane2:
    mov ax, [lanec2]
    jmp move_red_left_store

move_red_left_lane1:
    mov ax, [lanec1]

move_red_left_store:
    sub ax, CARHALFW
    mov [redx], ax

    pop ax
    ret


; move red car right between lanes
move_red_right:
    push ax

    mov al, [red_lane]
    cmp al, 2
    jae move_red_right_no_inc
    inc al
    mov [red_lane], al
move_red_right_no_inc:
    xor ah, ah

    cmp ax, 0
    je move_red_right_lane1
    cmp ax, 1
    je move_red_right_lane2
    mov ax, [lanec3]
    jmp move_red_right_store

move_red_right_lane2:
    mov ax, [lanec2]
    jmp move_red_right_store

move_red_right_lane1:
    mov ax, [lanec1]

move_red_right_store:
    sub ax, CARHALFW
    mov [redx], ax

    pop ax
    ret


; check collision between red car and all blue cars
check_blue_collisions:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    mov word [game_over_flag], 0

    mov ax, [redx]
    add ax, CARHALFW
    mov bx, ax

    mov ax, bx
    sub ax, [lanec1]
    jns cbc_abs1
    neg ax
cbc_abs1:
    mov dx, ax
    mov byte [red_lane], 0

    mov ax, bx
    sub ax, [lanec2]
    jns cbc_abs2
    neg ax
cbc_abs2:
    cmp ax, dx
    jge cbc_check3
    mov dx, ax
    mov byte [red_lane], 1

cbc_check3:
    mov ax, bx
    sub ax, [lanec3]
    jns cbc_abs3
    neg ax
cbc_abs3:
    cmp ax, dx
    jge cbc_lane_done
    mov byte [red_lane], 2

cbc_lane_done:

    mov ax, [redx]
    mov [red_left], ax
    add ax, CARW
    mov [red_right], ax
    mov ax, [redy]
    mov [red_top], ax
    add ax, CARH
    mov [red_bottom], ax

    mov al, [red_lane]

    xor si, si
cbc_loop:
    call get_blue_car_ptr

    mov dx, [bx]
    cmp dx, 0
    je cbc_next

    mov dx, [bx + 4]
    cmp dx, 0FFFFh
    je cbc_next
    cmp dx, SCR_HEIGHT
    jge cbc_next

    cmp al, [bx + 8]
    jne cbc_next

    mov cx, [bx + 2]
    mov di, cx
    add di, CARW
    mov dx, [bx + 4]
    push ax
    mov ax, dx
    add ax, CARH
    mov bp, ax
    pop ax

    mov dx, [red_right]
    cmp dx, cx
    jle cbc_next

    mov dx, [red_left]
    cmp di, dx
    jle cbc_next

    mov dx, [red_bottom]
    push ax
    mov ax, [bx + 4]
    cmp dx, ax
    pop ax
    jle cbc_next

    mov dx, [red_top]
    cmp bp, dx
    jle cbc_next

    mov word [game_over_flag], 1
    jmp cbc_done

cbc_next:
    inc si
    cmp si, MAX_BLUE_CARS
    jb cbc_loop

cbc_done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; draw road and background
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
    jb bg_outside_road
    cmp ax, ROADR
    ja bg_outside_road

    mov ax, si
    sub ax, ROADL
    cmp ax, BORDERW
    jb bg_border

    mov ax, ROADR
    sub ax, si
    cmp ax, BORDERW
    jb bg_border

    mov al, COL_ASPHALT

    mov dx, si
    cmp dx, [lane1]
    je bg_maybe_dash
    cmp dx, [lane2]
    je bg_maybe_dash
    jmp bg_write_pixel
        
bg_border:
    mov al, COL_BORDER
    jmp bg_write_pixel
        
bg_maybe_dash:
    test bp, 3
    jnz bg_write_pixel
    mov al, COL_LANEYELLOW
    jmp bg_write_pixel
        
bg_outside_road:
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


; draw red car at (CX,DX)
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
    cmp al, -1
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


; draw blue car with clipping at (CX,DX)
draw_car_blue:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    mov bp, dx
    add bp, CARH
    
    mov si, 0
    cmp dx, 0
    jge blue_start_ok
    
    neg dx
    mov si, dx
    mov dx, 0
    
blue_start_ok:
    mov ax, bp
    sub ax, dx
    cmp ax, CARH
    jbe blue_height_ok
    mov ax, CARH
blue_height_ok:
    cmp ax, 0
    jle blue_draw_done
    
    cmp dx, SCR_HEIGHT
    jge blue_draw_done
    
    mov bx, dx
    add bx, ax
    cmp bx, SCR_HEIGHT
    jbe blue_no_bottom_clip
    mov ax, SCR_HEIGHT
    sub ax, dx
    
blue_no_bottom_clip:
    mov bp, ax
    
    mov ax, dx
    push dx
    mov bx, SCR_WIDTH
    mul bx
    mov di, ax
    add di, cx
    pop dx

    mov ax, si
    mov bx, CARW
    mul bx
    mov si, car_blue_sprite
    add si, ax

    mov cx, bp
    
draw_blue_row:
    push cx
    push di
    mov cx, CARW
    
draw_blue_col:
    lodsb
    cmp al, -1
    jz  draw_blue_skip
    cmp al, 12
    jne chk_blue_red
    mov al, 9
    jmp blue_store

chk_blue_red:
    cmp al, 4
    jne chk_blue_dark
    mov al, 1
    jmp blue_store

chk_blue_dark:
    cmp al, 3
    jne blue_store
    mov al, 1
    
blue_store:
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


; draw 12x12 coin circle centered at AX,DX
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

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; draw fuel bar graphics at bottom
draw_fuel_hud: 
    pusha

    mov ah, 02h
    xor bh, bh
    mov dh, 22
    mov dl, 2
    int 10h

    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Ah

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
    mov si, 8
    mov ax, bp
    mov bx, SCR_WIDTH
    mul bx
    mov di, ax
    add di, si 
    mov cx, 12

drawfuel:
    push di 
    call drawfuelbar
    add di, 4 
    loop drawfuel

    popa
    ret


drawfuelbar:
    push bp 
    mov bp, sp 
    pusha 
    mov di, [bp+4] 

    mov bx, 8
fuel_row_loop:
    push di 
    mov cx, 2
fuel_col_loop:
    mov al, 2
    mov [es:di], al
    inc di
    loop fuel_col_loop
    pop di 
    add di, SCR_WIDTH
    dec bx
    jnz fuel_row_loop

    popa
    pop bp
    ret 2


; print coin HUD text and value
draw_coin_hud:
    pusha

    mov ah, 02h
    xor bh, bh
    mov dh, 0
    mov dl, 0
    int 10h

    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Fh
    mov si, msg_coins
draw_coin_label:
    lodsb
    or al, al
    jz draw_coin_label_done
    int 10h
    jmp draw_coin_label
draw_coin_label_done:

    mov ax, [coin_count]
    call print_dec

    popa
    ret


; print fuel HUD text and value
draw_fuel_text:
    pusha

    mov ah, 02h
    xor bh, bh
    mov dh, 1
    mov dl, 0
    int 10h

    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Fh
    mov si, msg_fuel
draw_fuel_label:
    lodsb
    or al, al
    jz draw_fuel_label_done
    int 10h
    jmp draw_fuel_label
draw_fuel_label_done:

    mov ax, [fuel_value]
    call print_dec

    popa
    ret


; print AX as unsigned decimal
print_dec:
    push ax
    push bx
    push cx
    push dx
    push si

    mov si, digit_buf + 4
    mov bx, 10
    xor cx, cx

    cmp ax, 0
    jne print_dec_conv
    mov byte [si], '0'
    mov cx, 1
    jmp print_dec_print

print_dec_conv:
print_dec_div_loop:
    xor dx, dx
    div bx
    add dl, '0'
    mov [si], dl
    dec si
    inc cx
    cmp ax, 0
    jne print_dec_div_loop

print_dec_print:
    inc si
print_dec_print_loop:
    mov al, [si]
    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Fh
    int 10h
    inc si
    loop print_dec_print_loop

    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; start menu screen
show_start_screen:
    pusha

    mov ax, VIDSEG
    mov es, ax
    xor di, di
    mov al, 0
    mov cx, SCR_WIDTH*SCR_HEIGHT
    rep stosb

    mov ah, 02h
    xor bh, bh
    mov dh, 8
    mov dl, 8
    int 10h

    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Eh
    mov si, msg_title
show_title:
    lodsb
    or al, al
    jz show_title_done
    int 10h
    jmp show_title
show_title_done:

    mov ah, 02h
    xor bh, bh
    mov dh, 12
    mov dl, 8
    int 10h

    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Fh
    mov si, msg_menu_play
show_play:
    lodsb
    or al, al
    jz show_play_done
    int 10h
    jmp show_play
show_play_done:

    mov ah, 02h
    xor bh, bh
    mov dh, 14
    mov dl, 8
    int 10h

    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Fh
    mov si, msg_menu_exit
show_exit:
    lodsb
    or al, al
    jz show_exit_done
    int 10h
    jmp show_exit
show_exit_done:

    mov ah, 02h
    xor bh, bh
    mov dh, 22
    mov dl, 8
    int 10h

    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Fh
    mov si, msg_credit1
show_credit1:
    lodsb
    or al, al
    jz show_credit1_done
    int 10h
    jmp show_credit1
show_credit1_done:

    mov ah, 02h
    xor bh, bh
    mov dh, 23
    mov dl, 8
    int 10h

    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Fh
    mov si, msg_credit2
show_credit2:
    lodsb
    or al, al
    jz show_credit2_done
    int 10h
    jmp show_credit2
show_credit2_done:

show_menu_wait:
    mov ah, 0
    int 16h
    cmp al, 'p'
    je show_menu_play_choice
    cmp al, 'P'
    je show_menu_play_choice
    cmp al, 'e'
    je show_menu_exit_choice
    cmp al, 'E'
    je show_menu_exit_choice
    jmp show_menu_wait

show_menu_play_choice:
    popa
    ret

show_menu_exit_choice:
    popa
    jmp near exit_to_dos


; overlay "Press S to start"
show_press_to_start_overlay:
    pusha

    mov ah, 02h
    xor bh, bh
    mov dh, 21
    mov dl, 22
    int 10h

    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Fh
    mov si, msg_start_prompt
sps_print:
    lodsb
    or al, al
    jz sps_print_done
    int 10h
    jmp sps_print
sps_print_done:

sps_wait:
    mov ah, 0
    int 16h
    cmp al, 's'
    je sps_accept
    cmp al, 'S'
    je sps_accept
    jmp sps_wait

sps_accept:
    call redraw_full_scene
    popa
    ret


; confirm exit on ESC, returns AL=1 yes, AL=0 no
confirm_exit:
    pusha

    mov ax, VIDSEG
    mov es, ax

    mov bx, 70
ce_row:
    mov ax, bx
    mov cx, SCR_WIDTH
    mul cx
    add ax, 80
    mov di, ax
    mov cx, 160
    mov al, 1
    rep stosb

    inc bx
    cmp bx, 130
    jbe ce_row

    mov ah, 02h
    xor bh, bh
    mov dh, 12
    mov dl, 11
    int 10h

    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Fh
    mov si, msg_confirm_exit
ce_print:
    lodsb
    or al, al
    jz ce_print_done
    int 10h
    jmp ce_print
ce_print_done:

ce_wait_key:
    mov ah, 0
    int 16h
    cmp al, 'y'
    je ce_yes
    cmp al, 'Y'
    je ce_yes
    cmp al, 'n'
    je ce_no
    cmp al, 'N'
    je ce_no
    jmp ce_wait_key

ce_yes:
    mov byte [confirm_choice], 1
    jmp ce_end

ce_no:
    mov byte [confirm_choice], 0

ce_end:
    popa
    mov al, [confirm_choice]
    ret


; redraw full scene (road, coins, blue cars, red car, HUD)
redraw_full_scene:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    call draw_background

    xor si, si
rfs_coin_loop:
    mov bx, si
    shl bx, 1
    cmp word [coin_active + bx], 0
    je rfs_next_coin
    mov ax, [coin_x + bx]
    mov dx, [coin_y + bx]
    call draw_coin_circle
rfs_next_coin:
    inc si
    cmp si, 3
    jb rfs_coin_loop

    call draw_all_blue_cars

    mov cx, [redx]
    mov dx, [redy]
    call draw_car_red

    call draw_fuel_hud
    call draw_coin_hud
    call draw_fuel_text

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; game over text
game_over_screen:
    pusha

    mov ah, 02h
    xor bh, bh
    mov dh, 12
    mov dl, 30
    int 10h

    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Ch
    mov si, msg_game_over
gos_line1:
    lodsb
    or al, al
    jz gos_line1_done
    int 10h
    jmp gos_line1
gos_line1_done:

    mov ah, 02h
    xor bh, bh
    mov dh, 14
    mov dl, 24
    int 10h

    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Fh
    mov si, msg_press_key
gos_line2:
    lodsb
    or al, al
    jz gos_line2_done
    int 10h
    jmp gos_line2
gos_line2_done:

    popa
    ret


; random number 0..BX-1, returns AX
getrandom:
    push dx
    push cx
    cmp bx, 1
    ja gr_mod_ok
    xor ax, ax
    jmp gr_exit
    
gr_mod_ok:
    mov ah, 0
    int 1Ah
    mov ax, dx
    xor dx, dx
    div bx
    mov ax, dx
    
gr_exit:
    pop cx
    pop dx
    ret


spawn_lane db 0
; sprite data and size
%include "redcar.inc"
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
tryw 14
tryw 15 
tryw 16
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
colstart   dw 0
colend     dw 0
lanec1     dw 0
lanec2     dw 0
lanec3     dw 0
xminc      dw 0
xmaxc      dw 0

; blue cars array: 14 bytes each
; +0: active (word)
; +2: x (word)
; +4: y (word)
; +6: bottom (word)
; +8: lane (byte)
; +10: old_x (word)
; +12: old_y (word)
blue_cars times (MAX_BLUE_CARS * 14) db 0

coin_base_x  dw 0
coin_base_y  dw 0

spawn_timer   dw 0

red_lane      db 0
red_left      dw 0
red_right     dw 0
red_top       dw 0
red_bottom    dw 0

game_over_flag dw 0

coin_active dw 0, 0, 0
coin_x     dw 0, 0, 0
coin_y     dw 0, 0, 0
coin_spawn_timer dw 0

coin_count   dw 0
fuel_value   dw 12
digit_buf    times 5 db 0

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

msg_game_over      db 'GAME OVER',0
msg_press_key      db 'Press any key to exit',0

msg_title          db 'BITBLAZER',0
msg_start_prompt   db 'Press S to start',0
msg_confirm_exit   db 'Exit to DOS? (Y/N)',0
confirm_choice     db 0

msg_menu_play      db 'P - Play',0
msg_menu_exit      db 'E - Exit',0
msg_credit1        db '24L-0598 Hareem Ahmad',0
msg_credit2        db '24L-0575 Laiba Fida',0

msg_coins          db 'COINS: ',0
msg_fuel           db 'FUEL: ',0
