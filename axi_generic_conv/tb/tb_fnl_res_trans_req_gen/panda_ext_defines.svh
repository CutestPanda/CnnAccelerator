`ifndef __PANDA_EXT_DEFINES_H
`define __PANDA_EXT_DEFINES_H

typedef int unsigned uint;
typedef int unsigned uint_queue[$];

typedef enum bit[1:0]{
	DATA_1_BYTE = 2'b00,
	DATA_2_BYTE = 2'b01,
	DATA_4_BYTE = 2'b10
}ofmap_data_type_t;

`endif
