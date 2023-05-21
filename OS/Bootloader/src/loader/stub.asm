%define LOADER_ARGS_SIZE 2

GLOBAL _start
GLOBAL loader_args

EXTERN main

[SECTION .text]
_start:
	; Set all segments to 0x10
	mov ax, 0x10
	mov ds, ax
	mov es, ax
	mov ss, ax
	mov fs, ax
	mov gs, ax

 	; Prepare stack
	mov esp, 0xFF0
	
	; ESI is already set to point to loader args structure.
	; CX should contain the size of the structure. If the passed size
	; is different than the one declared here, halt.
	cmp cx, LOADER_ARGS_SIZE
	jne halt
	
	; Copy the structure to our BSS section.
	mov edi, loader_args
	rep movsb
	
	call setupPagingStructures
	call enablePaging	
	call main		

halt:
	cli 
	hlt
	jmp halt

setupPagingStructures:
	; -- Page directory at 0x1000 --
	mov edi, 0x1000

	; Setup first page directory entry to 0x2000
	mov eax, 010000000000111b
	stosd

	; Zero-out the rest of the page directory entries. */
	xor eax, eax
	mov ecx, 1023
	rep stosd

	; -- Page table at 0x2000 -- */
	mov edi, 0x2000
	mov eax, 0000000000111b

	; Identity map 16 pages.*/
	mov ecx, 16
	.setpage:
		stosd
		add eax, 1000000000000b
	loop .setpage

	; Zero-out rest of page table entries */
	xor eax, eax
	mov ecx, 1008
	rep stosd
ret

enablePaging:
	; Set paging directory location
	mov eax, 0x1000
	mov cr3, eax

	; Enable paging
	mov eax, cr0
	or eax, 0x80000000
	mov cr0, eax
ret

[SECTION .bss]
loader_args: resb LOADER_ARGS_SIZE
