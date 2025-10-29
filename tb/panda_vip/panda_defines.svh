`ifndef __PANDA_DEFINES_H
`define __PANDA_DEFINES_H

`ifndef TIMEPRECISION
`define TIMEPRECISION 1ps
`endif

// `define EN_ICB_MASTER_AGT
// `define EN_ICB_SLAVE_AGT
`define EN_AXIS_MASTER_AGT
`define EN_AXIS_SLAVE_AGT

`ifndef PANDA_ICB_MAX_ADDR_WIDTH
	`define PANDA_ICB_MAX_ADDR_WIDTH 32
`endif

`ifndef PANDA_ICB_MAX_DATA_WIDTH
	`define PANDA_ICB_MAX_DATA_WIDTH 32
`endif

typedef enum{
	PANDA_ICB_ACCESS_TYPE_NOT_SET,
	PANDA_ICB_WRITE_ACCESS,
    PANDA_ICB_READ_ACCESS
}panda_icb_access_type;

typedef enum{
	PANDA_ICB_RSP_OK,
    PANDA_ICB_RSP_ERR
}panda_icb_response_type;

typedef logic[`PANDA_ICB_MAX_ADDR_WIDTH-1:0] panda_icb_address;
typedef logic[`PANDA_ICB_MAX_DATA_WIDTH-1:0] panda_icb_data;
typedef logic[`PANDA_ICB_MAX_DATA_WIDTH/8-1:0] panda_icb_strobe;

`ifndef PANDA_AXIS_MAX_DATA_WIDTH
	`define PANDA_AXIS_MAX_DATA_WIDTH 128
`endif

`ifndef PANDA_AXIS_MAX_USER_WIDTH
	`define PANDA_AXIS_MAX_USER_WIDTH 16
`endif

typedef logic[`PANDA_AXIS_MAX_DATA_WIDTH-1:0] panda_axis_data;
typedef logic[`PANDA_AXIS_MAX_DATA_WIDTH/8-1:0] panda_axis_mask;
typedef logic[`PANDA_AXIS_MAX_USER_WIDTH-1:0] panda_axis_user;

`endif
