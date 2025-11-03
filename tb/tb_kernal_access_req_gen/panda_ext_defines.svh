`ifndef __PANDA_EXT_DEFINES_H
`define __PANDA_EXT_DEFINES_H

typedef enum bit[2:0]{
	KBUFGRPSZ_1x1 = 3'b000,
	KBUFGRPSZ_3x3 = 3'b001,
	KBUFGRPSZ_5x5 = 3'b010,
	KBUFGRPSZ_7x7 = 3'b011,
	KBUFGRPSZ_9x9 = 3'b100,
	KBUFGRPSZ_11x11 = 3'b101
}kernal_sz_t;

`endif
