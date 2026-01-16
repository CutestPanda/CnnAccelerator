/**
通用逐元素操作处理单元IP配置参数:
	// 逐元素操作处理全局配置
	parameter integer ACCELERATOR_ID = 0; // 加速器ID(0~3)
	parameter integer MM2S_STREAM_DATA_WIDTH = 128; // MM2S通道DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer S2MM_STREAM_DATA_WIDTH = 128; // S2MM通道DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer ELEMENT_WISE_PROC_PIPELINE_N = 4; // 逐元素操作处理流水线条数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer FU_CLK_RATE = 2; // 功能单元的时钟倍率(1 | 2 | 4 | 8)
	// 输入与输出项字节数配置
	parameter integer IN_STRM_WIDTH_1_BYTE_SUPPORTED = 1; // 是否支持输入流项位宽为1字节
	parameter integer IN_STRM_WIDTH_2_BYTE_SUPPORTED = 1; // 是否支持输入流项位宽为2字节
	parameter integer IN_STRM_WIDTH_4_BYTE_SUPPORTED = 1; // 是否支持输入流项位宽为4字节
	parameter integer OUT_STRM_WIDTH_1_BYTE_SUPPORTED = 1; // 是否支持输出流项位宽为1字节
	parameter integer OUT_STRM_WIDTH_2_BYTE_SUPPORTED = 1; // 是否支持输出流项位宽为2字节
	parameter integer OUT_STRM_WIDTH_4_BYTE_SUPPORTED = 1; // 是否支持输出流项位宽为4字节
	// 输入数据转换单元配置
	parameter integer EN_IN_DATA_CVT = 1; // 启用输入数据转换单元
	parameter integer IN_DATA_CVT_EN_ROUND = 1; // 是否需要进行四舍五入
	parameter integer IN_DATA_CVT_FP16_IN_DATA_SUPPORTED = 0; // 是否支持FP16输入数据格式
	parameter integer IN_DATA_CVT_S33_IN_DATA_SUPPORTED = 1; // 是否支持S33输入数据格式
	// 计算单元配置
	parameter integer EN_POW2_CAL_UNIT = 1; // 启用二次幂计算单元
	parameter integer EN_MAC_UNIT = 1; // 启用乘加计算单元
	parameter integer CAL_EN_ROUND = 1; // 是否需要进行四舍五入
	parameter integer CAL_INT16_SUPPORTED = 0; // 是否支持INT16运算数据格式
	parameter integer CAL_INT32_SUPPORTED = 0; // 是否支持INT32运算数据格式
	parameter integer CAL_FP32_SUPPORTED = 1; // 是否支持FP32运算数据格式
	// 输出数据转换单元配置
	parameter integer EN_OUT_DATA_CVT = 1; // 启用输出数据转换单元
	parameter integer OUT_DATA_CVT_EN_ROUND = 1; // 是否需要进行四舍五入
	parameter integer OUT_DATA_CVT_S33_OUT_DATA_SUPPORTED = 1; // 是否支持S33输出数据格式
	// 舍入单元配置
	parameter integer EN_ROUND_UNIT = 1; // 启用舍入单元
	parameter integer ROUND_S33_ROUND_SUPPORTED = 1; // 是否支持S33数据的舍入
	parameter integer ROUND_FP32_ROUND_SUPPORTED = 0; // 是否支持FP32数据的舍入
	// 性能监测
	parameter integer EN_PERF_MON = 1; // 是否支持性能监测
**/

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#include "sd_card_fatfs.h"
#include "axi_element_wise_proc.h"

#include "xparameters.h"
#include "xil_cache.h"

#include <stdio.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static int element_wise_proc_test(const AxiElmWiseProcBufCfg* buf_cfg, const AxiElmWiseProcFuCfg* fu_cfg);

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define TO_FLUSH_DCACHE // 是否需要刷新DCache
#define OUTPUT_RES_TO_SDCARD // 是否需要将结果保存到SD卡

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static FATFS fatfs; // FAT32文件系统
static FIL file_handler; // 文件描述符

static AxiElmWiseProcHandler axi_element_wise_proc; // 通用逐元素操作处理单元
static AxiElmWiseProcPerfMonsts pm_sts; // 性能监测状态

static float op_x_buf[3 * 40 * 40 * 2]; // 操作数X缓存区
static float op_a_b_buf[3 * 40 * 40 * 2]; // 操作数A或B缓存区
static float res_buf[3 * 40 * 40 * 2]; // 结果缓存区

////////////////////////////////////////////////////////////////////////////////////////////////////////////

int main(){
	AxiElmWiseProcBufCfg buf_cfg; // 缓存区基地址和大小配置
	AxiElmWiseProcFuCfg fu_cfg; // 功能单元配置
	const float op_a_const_0 = 32.0f;

	// 初始化SD卡文件系统
	if(init_sd_card_fatfs(&fatfs, 0)){
		return -1;
	}

	// 初始化通用逐元素操作处理单元
	if(axi_element_wise_proc_init(&axi_element_wise_proc, XPAR_AXI_ELEMENT_WISE_PROC_0_BASEADDR)){
		return -1;
	}

	// 使能加速器
	if(axi_element_wise_proc_enable(&axi_element_wise_proc)){
		return -1;
	}

	/* 计算: 32X + B */
	// 从SD卡读取操作数X
	if(sd_card_fatfs_fopen(&file_handler, "op_x_0.bin", FA_READ, 0)){
		return -1;
	}

	if(sd_card_fatfs_fread(&file_handler, (void*)op_x_buf, 3 * 40 * 40 * 2 * 4) != 3 * 40 * 40 * 2 * 4){
		return -1;
	}
	if(sd_card_fatfs_fclose(&file_handler)){
		return -1;
	}

#ifdef TO_FLUSH_DCACHE
	Xil_DCacheFlushRange((INTPTR)op_x_buf, 3 * 40 * 40 * 2 * 4); // 刷新DCache
#endif

	// 从SD卡读取操作数B
	if(sd_card_fatfs_fopen(&file_handler, "op_b_0.bin", FA_READ, 0)){
		return -1;
	}

	if(sd_card_fatfs_fread(&file_handler, (void*)op_a_b_buf, 3 * 40 * 40 * 2 * 4) != 3 * 40 * 40 * 2 * 4){
		return -1;
	}
	if(sd_card_fatfs_fclose(&file_handler)){
		return -1;
	}

#ifdef TO_FLUSH_DCACHE
	Xil_DCacheFlushRange((INTPTR)op_a_b_buf, 3 * 40 * 40 * 2 * 4); // 刷新DCache
#endif

	buf_cfg.op_x_buf_baseaddr = (uint8_t*)op_x_buf;
	buf_cfg.op_a_b_buf_baseaddr = (uint8_t*)op_a_b_buf;
	buf_cfg.res_buf_baseaddr = (uint8_t*)res_buf;
	buf_cfg.op_x_buf_len = 3 * 40 * 40 * 2 * 4;
	buf_cfg.op_a_b_buf_len = 3 * 40 * 40 * 2 * 4;
	buf_cfg.res_buf_len = 3 * 40 * 40 * 2 * 4;

	fu_cfg.in_data_fmt = ELM_INFMT_FP32;
	fu_cfg.cal_fmt = ELM_CALFMT_FP32;
	fu_cfg.out_data_fmt = ELM_OUTFMT_FP32;
	fu_cfg.use_in_data_cvt_unit = 0;
	fu_cfg.use_pow2_cell = 0;
	fu_cfg.use_mac_cell = 1;
	fu_cfg.use_out_data_cvt_unit = 0;
	fu_cfg.use_round_cell = 0;

	fu_cfg.is_op_a_eq_1 = 0;
	fu_cfg.is_op_a_const = 1;
	fu_cfg.is_op_b_eq_0 = 0;
	fu_cfg.is_op_b_const = 0;
	fu_cfg.op_a_const_val_ptr = (uint32_t*)(&op_a_const_0);

#ifdef TO_FLUSH_DCACHE
	Xil_DCacheFlushRange((INTPTR)res_buf, 3 * 40 * 40 * 2 * 4); // 刷新DCache
#endif

	if(element_wise_proc_test((const AxiElmWiseProcBufCfg*)(&buf_cfg), (const AxiElmWiseProcFuCfg*)(&fu_cfg))){
		return -1;
	}

#ifdef TO_FLUSH_DCACHE
	Xil_DCacheFlushRange((INTPTR)res_buf, 3 * 40 * 40 * 2 * 4); // 刷新DCache
#endif

#ifdef OUTPUT_RES_TO_SDCARD
	// 将结果存回SD卡
	if(sd_card_fatfs_fopen(&file_handler, "res_0.bin", FA_WRITE | FA_CREATE_ALWAYS, 0)){
		return -1;
	}

	if(sd_card_fatfs_fwrite(&file_handler, (void*)res_buf, 3 * 40 * 40 * 2 * 4) != 3 * 40 * 40 * 2 * 4){
		return -1;
	}

	if(sd_card_fatfs_fclose(&file_handler)){
		return -1;
	}
#endif

	/* 计算: A * (X^2) */
	// 从SD卡读取操作数X
	if(sd_card_fatfs_fopen(&file_handler, "op_x_1.bin", FA_READ, 0)){
		return -1;
	}

	if(sd_card_fatfs_fread(&file_handler, (void*)op_x_buf, 3 * 40 * 40 * 2 * 4) != 3 * 40 * 40 * 2 * 4){
		return -1;
	}
	if(sd_card_fatfs_fclose(&file_handler)){
		return -1;
	}

#ifdef TO_FLUSH_DCACHE
	Xil_DCacheFlushRange((INTPTR)op_x_buf, 3 * 40 * 40 * 2 * 4); // 刷新DCache
#endif

	// 从SD卡读取操作数A
	if(sd_card_fatfs_fopen(&file_handler, "op_a_1.bin", FA_READ, 0)){
		return -1;
	}

	if(sd_card_fatfs_fread(&file_handler, (void*)op_a_b_buf, 3 * 40 * 40 * 2 * 4) != 3 * 40 * 40 * 2 * 4){
		return -1;
	}
	if(sd_card_fatfs_fclose(&file_handler)){
		return -1;
	}

#ifdef TO_FLUSH_DCACHE
	Xil_DCacheFlushRange((INTPTR)op_a_b_buf, 3 * 40 * 40 * 2 * 4); // 刷新DCache
#endif

	buf_cfg.op_x_buf_baseaddr = (uint8_t*)op_x_buf;
	buf_cfg.op_a_b_buf_baseaddr = (uint8_t*)op_a_b_buf;
	buf_cfg.res_buf_baseaddr = (uint8_t*)res_buf;
	buf_cfg.op_x_buf_len = 3 * 40 * 40 * 2 * 4;
	buf_cfg.op_a_b_buf_len = 3 * 40 * 40 * 2 * 4;
	buf_cfg.res_buf_len = 3 * 40 * 40 * 2 * 4;

	fu_cfg.in_data_fmt = ELM_INFMT_FP32;
	fu_cfg.cal_fmt = ELM_CALFMT_FP32;
	fu_cfg.out_data_fmt = ELM_OUTFMT_FP32;
	fu_cfg.use_in_data_cvt_unit = 0;
	fu_cfg.use_pow2_cell = 1;
	fu_cfg.use_mac_cell = 1;
	fu_cfg.use_out_data_cvt_unit = 0;
	fu_cfg.use_round_cell = 0;

	fu_cfg.is_op_a_eq_1 = 0;
	fu_cfg.is_op_a_const = 0;
	fu_cfg.is_op_b_eq_0 = 1;
	fu_cfg.is_op_b_const = 0;

#ifdef TO_FLUSH_DCACHE
	Xil_DCacheFlushRange((INTPTR)res_buf, 3 * 40 * 40 * 2 * 4); // 刷新DCache
#endif

	if(element_wise_proc_test((const AxiElmWiseProcBufCfg*)(&buf_cfg), (const AxiElmWiseProcFuCfg*)(&fu_cfg))){
		return -1;
	}

#ifdef TO_FLUSH_DCACHE
	Xil_DCacheFlushRange((INTPTR)res_buf, 3 * 40 * 40 * 2 * 4); // 刷新DCache
#endif

#ifdef OUTPUT_RES_TO_SDCARD
	// 将结果存回SD卡
	if(sd_card_fatfs_fopen(&file_handler, "res_1.bin", FA_WRITE | FA_CREATE_ALWAYS, 0)){
		return -1;
	}

	if(sd_card_fatfs_fwrite(&file_handler, (void*)res_buf, 3 * 40 * 40 * 2 * 4) != 3 * 40 * 40 * 2 * 4){
		return -1;
	}

	if(sd_card_fatfs_fclose(&file_handler)){
		return -1;
	}
#endif

	while(1);
}

static int element_wise_proc_test(const AxiElmWiseProcBufCfg* buf_cfg, const AxiElmWiseProcFuCfg* fu_cfg){
	// 清除DMA命令完成数计数器
	if(axi_element_wise_proc_clr_cmd_fns_n(&axi_element_wise_proc, ELM_C_ALL)){
		return -1;
	}

	// 清除性能监测计数器
	if(axi_element_wise_proc_clr_pm_cnt(&axi_element_wise_proc)){
		return -1;
	}

	// 配置通用逐元素操作处理单元
	if(axi_element_wise_proc_cfg(&axi_element_wise_proc, fu_cfg)){
		return -1;
	}

	// 使能数据枢纽与处理核心
	if(axi_element_wise_proc_enable_data_hub_and_proc_core(&axi_element_wise_proc)){
		return -1;
	}

	// 使能性能监测
	if(axi_element_wise_proc_enable_cycle_n_cnt(&axi_element_wise_proc)){
		return -1;
	}

	// 启动通用逐元素操作处理单元
	if(axi_element_wise_proc_start(
		&axi_element_wise_proc,
		buf_cfg,
		(!(fu_cfg->is_op_a_eq_1 || fu_cfg->is_op_a_const)) || (!(fu_cfg->is_op_b_eq_0 || fu_cfg->is_op_b_const)))
	){
		return -1;
	}

	// 等待逐元素操作处理完成(S2MM通道传输完成)
	while(axi_element_wise_proc_get_cmd_fns_n(&axi_element_wise_proc, ELM_Q_CMD_FNS_N_S2MM) < 1);

	// 除能性能监测
	axi_element_wise_proc_disable_cycle_n_cnt(&axi_element_wise_proc);

	// 除能数据枢纽与处理核心
	axi_element_wise_proc_disable_data_hub_and_proc_core(&axi_element_wise_proc);

	// 获取性能监测计数器的值
	if(axi_element_wise_proc_get_pm_cnt(&axi_element_wise_proc, &pm_sts)){
		return -1;
	}

	return 0;
}
