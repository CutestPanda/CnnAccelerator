`ifndef __PANDA_EXT_DEFINES_H
`define __PANDA_EXT_DEFINES_H

typedef int unsigned uint;
typedef int unsigned uint_queue[$];

typedef enum bit[3:0]{
	COLN_4 = 4'b0000,
	COLN_8 = 4'b0001,
	COLN_16 = 4'b0010,
	COLN_32 = 4'b0011,
	COLN_64 = 4'b0100,
	COLN_128 = 4'b0101,
	COLN_256 = 4'b0110,
	COLN_512 = 4'b0111,
	COLN_1024 = 4'b1000,
	COLN_2048 = 4'b1001,
	COLN_4096 = 4'b1010
}fmbuf_coln_t;

typedef enum bit[2:0]{
	KBUFGRPSZ_1x1 = 3'b000,
	KBUFGRPSZ_3x3 = 3'b001,
	KBUFGRPSZ_5x5 = 3'b010,
	KBUFGRPSZ_7x7 = 3'b011,
	KBUFGRPSZ_9x9 = 3'b100,
	KBUFGRPSZ_11x11 = 3'b101
}kernal_sz_t;

typedef enum bit[2:0]{
	WGTBLK_SFC_N_1 = 3'b000,
	WGTBLK_SFC_N_2 = 3'b001,
	WGTBLK_SFC_N_4 = 3'b010,
	WGTBLK_SFC_N_8 = 3'b011,
	WGTBLK_SFC_N_16 = 3'b100,
	WGTBLK_SFC_N_32 = 3'b101,
	WGTBLK_SFC_N_64 = 3'b110,
	WGTBLK_SFC_N_128 = 3'b111
}wgtblk_sfc_n_t;

`endif
