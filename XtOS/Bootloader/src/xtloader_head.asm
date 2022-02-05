[BITS 16]
[CPU 386]
[ORG 0x700]

/* Author:   André Morales 
   Version:  0.6.2
   Creation: 02/01/2021
   Modified: 25/01/2022 */

; Physical Map
; -- [0x0500] Stack
; -- [0x0700] Stage 3 (us)
; -- [0x1000] FAT16 Cluster Buffer
; -- [0x1000] Page directory
; -- [0x2000] Stage 4 file will be loaded here
; -- [0x2000] Page table
; -- [0x3000] Stage 4 code starts here

#include version_h.asm
#include <stdconio_h.asm>

%define FAT16_CLUSTER_BUFFER_ADDR 0x1000
%define STAGE4_FILE_ADDR 0x2000

%define PAGE_DIRECTORY 0x1000
%define PAGE_TABLE 0x2000

%define STAGE4_EXEC_ADDR 0x3000

jmp Start

dw Drive ; Stores in the binary a pointer to the beginning of the Drive variables and the FATFS variables. 
dw FATFS ; These pointers are used by Stage 2 to transfer the state to Stage 3 when loading it.

var short ELF.fileLocation
var int ELF.entryPoint
var int ELF.progHeaderTable
var word ELF.progHeaderSize
var word ELF.progHeaderCount

; Variables to be passed to XtLoader
var void XtLoaderStruct
	var byte vidmode.columns
	var byte vidmode.id
var void XtLoaderStruct.end

Start: {
	Print(."\N-- XtLoader Head ${VERSION}")

	mov word [Drive.bufferPtr], STAGE4_FILE_ADDR
	mov word [FATFS.clusterBuffer], FAT16_CLUSTER_BUFFER_ADDR

	Print(."\NLoading XTLOADER.ELF\N")
	mov si, ."XTOS       /XTLOADERELF"
	call FATFS.FindFile
	
	mov word [Drive.bufferPtr], STAGE4_FILE_ADDR
	push ax
	call FATFS.ReadClusterChain
	
	mov word [ELF.fileLocation], STAGE4_FILE_ADDR
	call LoadELF
	Print(."\NExecutable loaded.")

	call SetupPagingStructures
	call GetInfo
	
	Print(."\NPress any key to execute XtLdr32.")
	Getch()
	jmp Enable32
}

GetInfo: {
	; Get current video mode
	mov ah, 0Fh
	int 10h
	mov byte [vidmode.id], al
	mov byte [vidmode.columns], ah
	
	mov al, ah
	xor ah, ah
	
	Print(."\NVideo columns: ")
	PrintDecNum ax
	
	mov al, [vidmode.id]
	Print(."\NVideo mode: ")
	PrintDecNum ax
ret }

Enable32: {
	Print(."\NEntering 32-bit...")

	cli             ; Interrupts clear.
	lgdt [GDT_Desc] ; Load GDT
	
	; Set Protected Mode bit
	mov eax, cr0
	or al, 1
	mov cr0, eax
	
	jmp 08h:Entry32 ; Far jump to set CS
}

[BITS 32]
Entry32: {
	; Set all segments to data segment
	mov ax, 0x10
	mov ds, ax
	mov es, ax
	mov fs, ax
	mov gs, ax
	mov ss, ax
	
	; Enable paging
	mov eax, PAGE_DIRECTORY
	mov cr3, eax
	
	mov eax, cr0
	or eax, 0x80000000
	mov cr0, eax

	; Setup stack
	mov esp, 0x7FF0
	mov edx, [ELF.entryPoint] ; Save entry point on EDX
	
	; Set ESI to variables to be passed and jump
	mov esi, XtLoaderStruct
	jmp edx
.End: }

[BITS 16]

SetupPagingStructures: {
	/* -- Setup page directory -- */
	; Set the first Page Directory Entry to point to a Page Table at 0x2000
	;                       P P U R
	;                 P     C W / /
	;             -   S - A D T S W P
	mov eax, 010_0000_0_0_0_1_0_1_1_1b
	mov di, PAGE_DIRECTORY
	stosd
	
	mov cx, 1023 ; Fill the remaining 1023 entries with nothing
	xor eax, eax
	rep stosd
	
	/* -- Setup page table -- */
	; Configure the flags we'll use for the pages
	;                P     P P U R
	;                A     C W / /
	;           -  G T D A D T S W P 
	mov eax, 0_000_0_0_0_0_1_0_1_1_1b
		
	mov cx, 16 ; Identity page this many 4kb pages.
	mov di, PAGE_TABLE
	.setPage:
		stosd
		add eax, 0b1_000000000000
	loop .setPage
	
	; Fill the remaining page table entries with 0.
	mov cx, 1008
	xor eax, eax
	rep stosd
ret }

; Loads the ELF file present at 0x3000.
LoadELF: {
	push bp
	mov bp, sp

	mov bx, [ELF.fileLocation]
	call LoadELFHeader
	call LoadProgramSegments
	
	mov sp, bp
	pop bp
ret }

LoadELFHeader: {
	; Make sure the file is an ELF file in the first place.
	cmp word [bx + 0], 0x457F | jne NotAnElf
	cmp word [bx + 2], 0x464C | jne NotAnElf
	
	mov eax, [bx + 24]
	mov [ELF.entryPoint], eax
	
	mov ax, [bx + 28]
	mov [ELF.progHeaderTable], ax
	
	mov ax, [bx + 42]
	mov [ELF.progHeaderSize], ax
	
	mov ax, [bx + 44]
	mov [ELF.progHeaderCount], ax
	
	PrintDecNum [ELF.progHeaderCount]
	Print(." entries of ")
	PrintDecNum [ELF.progHeaderSize]
	Print(." bytes at 0x")
	PrintHexNum word [ELF.progHeaderTable]
	Print(."\NEntry: ")
	PrintDecNum word [ELF.entryPoint]
ret }

LoadProgramSegments: {	
	mov cx, [ELF.progHeaderCount]
	mov si, [ELF.progHeaderTable]
	lea si, [si + bx]
	.loadSegment:
		call LoadSegment
		add si, [ELF.progHeaderSize]
	loop .loadSegment
ret }

var void p_header
	var int p_offset
	var int p_vaddr
	var int p_filesz
	var int p_memsz

LoadSegment: {
	push si | push cx
	
	; Copy (and print) segment info
	mov di, p_header
	
	; p_offset
	add si, 4
	movsw
	movsw
	; p_vaddr
	movsw
	movsw
	; p_filesz (size of this segment in the file)
	add si, 4
	movsw
	movsw
	; p_memsz
	movsw
	movsw
	
	Print(."\Np_offset ")
	PrintDecNum [p_offset]
	
	Print(."\Np_vaddr ")
	PrintDecNum [p_vaddr]
	
	Print(."\Np_filesz ")
	PrintDecNum [p_filesz]
	
	Print(."\Np_memsz ")
	PrintDecNum [p_memsz]
	
	; Load segment into ram
	mov bx, [ELF.fileLocation]
	mov si, [p_offset]
	lea si, [si + bx]
	
	mov di, STAGE4_EXEC_ADDR
	
	mov cx, [p_filesz]
	rep movsb
	
	pop cx | pop si
ret }

NotAnElf:
	Print(."\NNot an ELF file!");
	jmp Halt

Halt:
	Print(."\NHalted.\N")
	cli | hlt
	
FileNotFoundOnDir: {
	Print(."\NFile '")
	mov si, [FATFS.filePathPtr]
	call print
	
	Print(."' not found on directory.")
	jmp Halt
}

; Code imports
#include <stdconio.asm>
#include <drive.asm>
#include <fat1x.asm>

@rodata:

; Global descriptor table imported by LGDT instruction
GDT:
	; Entry 0 must be null
	dq 0     

	; Entry 1 (CS)
	dw 0xFFFF ; Limit (0:15)
	dw 0      ; Base (0:15)
	db 0      ; Base (16:23)
	db 10011010b
	db 11001111b
	db 0
	
	; Entry 2 (DS)
	dw 0xFFFF ; Limit (0:15)
	dw 0      ; Base (0:15)
	db 0      ; Base (16:23)
	db 10010010b
	db 11001111b
	db 0
GDT_End:

GDT_Desc:
	dw GDT_End - GDT
	dd GDT

GDT_Desc_End:

@data: