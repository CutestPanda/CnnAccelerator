/************************************************************************************************************************
通用逐元素操作处理单元驱动(接口头文件)
@brief  提供了通用逐元素操作处理的初始化、控制、状态获取、配置等API
@date   2026/01/16
@author 陈家耀
@eidt   2026.01.16 1.00 创建了第1个正式版本
************************************************************************************************************************/

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 枚举类型: DMA命令完成数查询类别
typedef enum{
	ELM_Q_CMD_FNS_N_MM2S_0,
	ELM_Q_CMD_FNS_N_MM2S_1,
	ELM_Q_CMD_FNS_N_S2MM
}AxiElmWiseProcCmdFnsNQueryType;

// 枚举类型: DMA命令完成数(计数器)清除类别
typedef enum{
	ELM_C_CMD_FNS_N_MM2S_0,
	ELM_C_CMD_FNS_N_MM2S_1,
	ELM_C_CMD_FNS_N_S2MM,
	ELM_C_ALL
}AxiElmWiseProcCmdFnsNClrType;

// 枚举类型: 输入数据格式
typedef enum{
	ELM_INFMT_U8 = 0,
	ELM_INFMT_S8 = 1,
	ELM_INFMT_U16 = 2,
	ELM_INFMT_S16 = 3,
	ELM_INFMT_U32 = 4,
	ELM_INFMT_S32 = 5,
	ELM_INFMT_FP16 = 6,
	ELM_INFMT_FP32 = 7 // 实际数据格式为NONE
}AxiElmWiseProcInDataFmt;

// 枚举类型: 运算数据格式
typedef enum{
	ELM_CALFMT_S16 = 0,
	ELM_CALFMT_S32 = 1,
	ELM_CALFMT_FP32 = 2
}AxiElmWiseProcCalFmt;

// 枚举类型: 输出数据格式
typedef enum{
	ELM_OUTFMT_U8 = 0,
	ELM_OUTFMT_S8 = 1,
	ELM_OUTFMT_U16 = 2,
	ELM_OUTFMT_S16 = 3,
	ELM_OUTFMT_U32 = 4,
	ELM_OUTFMT_S32 = 5,
	ELM_OUTFMT_FP16 = 6,
	ELM_OUTFMT_FP32 = 7 // 实际数据格式为NONE
}AxiElmWiseProcOutDataFmt;

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 结构体: 加速器属性
typedef struct{
	char version[9]; // 版本号
	char accelerator_type[7]; // 加速器类型
	uint8_t accelerator_id; // 加速器ID

	uint16_t mm2s_stream_data_width; // MM2S通道DMA数据流的位宽
	uint16_t s2mm_stream_data_width; // S2MM通道DMA数据流的位宽

	uint8_t element_wise_proc_pipeline_n; // 逐元素操作处理流水线条数

	uint8_t exist_in_data_cvt_unit; // 存在输入数据转换单元
	uint8_t exist_pow2_cell; // 存在二次幂计算单元
	uint8_t exist_mac_cell; // 存在乘加计算单元
	uint8_t exist_out_data_cvt_unit; // 存在输出数据转换单元
	uint8_t exist_round_cell; // 存在舍入单元

	uint8_t performance_monitor_supported; // 是否支持性能监测

	uint8_t in_stream_width_1B_supported; // 是否支持输入流项位宽为1字节
	uint8_t in_stream_width_2B_supported; // 是否支持输入流项位宽为2字节
	uint8_t in_stream_width_4B_supported; // 是否支持输入流项位宽为4字节
	uint8_t out_stream_width_1B_supported; // 是否支持输出流项位宽为1字节
	uint8_t out_stream_width_2B_supported; // 是否支持输出流项位宽为2字节
	uint8_t out_stream_width_4B_supported; // 是否支持输出流项位宽为4字节
	uint8_t in_data_cvt_fp16_to_fp32_supported; // 是否支持输入FP16转FP32
	uint8_t in_data_cvt_int_to_fp32_supported; // 是否支持输入整型转FP32
	uint8_t cal_fmt_s16_supported; // 是否支持S16运算数据格式
	uint8_t cal_fmt_s32_supported; // 是否支持S32运算数据格式
	uint8_t cal_fmt_fp32_supported; // 是否支持FP32运算数据格式
	uint8_t out_data_cvt_fp32_to_s33_supported; // 是否支持输出FP32转S33
	uint8_t round_s33_supported; // 是否支持S33数据的舍入
	uint8_t round_fp32_supported; // 是否支持FP32舍入为FP16
}AxiElmWiseProcProp;

// 结构体: 寄存器域(属性)
typedef struct{
	uint32_t version;
	uint32_t acc_name;
	uint32_t info0;
	uint32_t info1;
}AxiElmWiseProcRegRgnProp;

// 结构体: 寄存器域(控制)
typedef struct{
	uint32_t ctrl0;
	uint32_t ctrl1;
}AxiElmWiseProcRegRgnCtrl;

// 结构体: 寄存器域(状态)
typedef struct{
	uint32_t sts0;
	uint32_t sts1;
	uint32_t sts2;
	uint32_t sts3;
}AxiElmWiseProcRegRgnSts;

// 结构体: 寄存器域(缓存区配置)
typedef struct{
	uint32_t buf_cfg0;
	uint32_t buf_cfg1;
	uint32_t buf_cfg2;
	uint32_t buf_cfg3;
	uint32_t buf_cfg4;
	uint32_t buf_cfg5;
}AxiElmWiseProcRegRgnBufCfg;

// 结构体: 寄存器域(功能单元配置)
typedef struct{
	uint32_t fmt_cfg;
	uint32_t fixed_point_cfg0;
	uint32_t fixed_point_cfg1;
	uint32_t op_a_b_cfg0;
	uint32_t op_a_b_cfg1;
	uint32_t op_a_b_cfg2;
	uint32_t fu_bypass_cfg;
}AxiElmWiseProcRegRgnFuCfg;

// 结构体: 子配置参数(缓存区基地址和大小)
typedef struct{
	uint8_t* op_x_buf_baseaddr; // 操作数X缓存区基地址
	uint8_t* op_a_b_buf_baseaddr; // 操作数A或B缓存区基地址
	uint8_t* res_buf_baseaddr; // 结果缓存区基地址

	uint32_t op_x_buf_len; // 操作数X缓存区大小
	uint32_t op_a_b_buf_len; // 操作数A或B缓存区大小
	uint32_t res_buf_len; // 结果缓存区大小
}AxiElmWiseProcBufCfg;

// 结构体: 子配置参数(功能单元)
typedef struct{
	AxiElmWiseProcInDataFmt in_data_fmt; // 输入数据格式
	AxiElmWiseProcCalFmt cal_fmt; // 计算数据格式
	AxiElmWiseProcOutDataFmt out_data_fmt; // 输出数据格式

	uint8_t use_in_data_cvt_unit; // 使用输入数据转换单元
	uint8_t use_pow2_cell; // 使用二次幂计算单元
	uint8_t use_mac_cell; // 使用乘加计算单元
	uint8_t use_out_data_cvt_unit; // 使用输出数据转换单元
	uint8_t use_round_cell; // 使用舍入单元

	uint8_t in_fixed_point_quat_accrc; // 输入定点数量化精度
	uint8_t op_x_fixed_point_quat_accrc; // 操作数X的定点数量化精度
	uint8_t op_a_fixed_point_quat_accrc; // 操作数A的定点数量化精度
	uint8_t s33_cvt_fixed_point_quat_accrc; // 转换为S33输出数据的定点数量化精度
	uint8_t round_in_fixed_point_quat_accrc; // 舍入单元输入定点数量化精度
	uint8_t round_out_fixed_point_quat_accrc; // 舍入单元输出定点数量化精度

	uint8_t is_op_a_eq_1; // 操作数A的实际值恒为1
	uint8_t is_op_b_eq_0; // 操作数B的实际值恒为0
	uint8_t is_op_a_const; // 操作数A为常量
	uint8_t is_op_b_const; // 操作数B为常量

	uint32_t* op_a_const_val_ptr; // 操作数A的常量值(指针)
	uint32_t* op_b_const_val_ptr; // 操作数B的常量值(指针)
}AxiElmWiseProcFuCfg;

// 结构体: 性能监测状态
typedef struct{
	uint32_t cycle_n; // 运行周期数
}AxiElmWiseProcPerfMonsts;

// 结构体: 通用逐元素操作处理单元
typedef struct{
	uint32_t* reg_base_ptr; // 寄存器区基地址

	// 寄存器域
	AxiElmWiseProcRegRgnProp* reg_region_prop; // 寄存器域(属性)
	AxiElmWiseProcRegRgnCtrl* reg_region_ctrl; // 寄存器域(控制)
	AxiElmWiseProcRegRgnSts* reg_region_sts; // 寄存器域(状态)
	AxiElmWiseProcRegRgnBufCfg* reg_region_buf_cfg; // 寄存器域(缓存区配置)
	AxiElmWiseProcRegRgnFuCfg* reg_region_fu_cfg; // 寄存器域(功能单元配置)

	AxiElmWiseProcProp property; // 加速器属性
}AxiElmWiseProcHandler;

////////////////////////////////////////////////////////////////////////////////////////////////////////////

int axi_element_wise_proc_init(AxiElmWiseProcHandler* handler, uint32_t baseaddr); // 初始化通用逐元素操作处理单元

int axi_element_wise_proc_enable(AxiElmWiseProcHandler* handler); // 使能加速器
void axi_element_wise_proc_disable(AxiElmWiseProcHandler* handler); // 除能加速器
int axi_element_wise_proc_enable_data_hub_and_proc_core(AxiElmWiseProcHandler* handler); // 使能数据枢纽与处理核心
void axi_element_wise_proc_disable_data_hub_and_proc_core(AxiElmWiseProcHandler* handler); // 除能数据枢纽与处理核心
int axi_element_wise_proc_enable_cycle_n_cnt(AxiElmWiseProcHandler* handler); // 使能运行周期数计数器
void axi_element_wise_proc_disable_cycle_n_cnt(AxiElmWiseProcHandler* handler); // 除能运行周期数计数器
int axi_element_wise_proc_start(AxiElmWiseProcHandler* handler, const AxiElmWiseProcBufCfg* buf_cfg, uint8_t use_op_a_or_b); // 启动通用逐元素操作处理单元

int axi_element_wise_proc_cfg(AxiElmWiseProcHandler* handler, const AxiElmWiseProcFuCfg* cfg); // 配置通用逐元素操作处理单元

uint32_t axi_element_wise_proc_get_cmd_fns_n(AxiElmWiseProcHandler* handler, AxiElmWiseProcCmdFnsNQueryType query_type); // 查询DMA命令完成数
int axi_element_wise_proc_clr_cmd_fns_n(AxiElmWiseProcHandler* handler, AxiElmWiseProcCmdFnsNClrType clr_type); // 清除DMA命令完成数计数器
int axi_element_wise_proc_get_pm_cnt(AxiElmWiseProcHandler* handler, AxiElmWiseProcPerfMonsts* pm_sts); // 获取性能监测计数器的值
int axi_element_wise_proc_clr_pm_cnt(AxiElmWiseProcHandler* handler); // 清除性能监测计数器
