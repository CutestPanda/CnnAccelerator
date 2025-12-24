/**
通用池化处理单元IP配置参数:
	parameter integer ACCELERATOR_ID = 0; // 加速器ID(0~3)
	parameter integer MAX_POOL_SUPPORTED = 1; // 是否支持最大池化
	parameter integer AVG_POOL_SUPPORTED = 0; // 是否支持平均池化
	parameter integer UP_SAMPLE_SUPPORTED = 1; // 是否支持上采样
	parameter integer POST_MAC_SUPPORTED = 0; // 是否支持后乘加处理
	parameter integer INT8_SUPPORTED = 0; // 是否支持INT8运算数据格式
	parameter integer INT16_SUPPORTED = 0; // 是否支持INT16运算数据格式
	parameter integer FP16_SUPPORTED = 1; // 是否支持FP16运算数据格式
	parameter integer EXT_PADDING_SUPPORTED = 1; // 是否支持外填充
	parameter integer NON_ZERO_CONST_PADDING_SUPPORTED = 0; // 是否支持非0常量填充模式
	parameter integer EN_PERF_MON = 1; // 是否支持性能监测
	parameter integer KEEP_FP32_OUT = 0; // 是否保持FP32输出
	
	parameter integer ATOMIC_C = 8; // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer POST_MAC_PRL_N = 1; // 后乘加并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer MM2S_STREAM_DATA_WIDTH = 64; // MM2S通道DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer S2MM_STREAM_DATA_WIDTH = 64; // S2MM通道DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer CBUF_BANK_N = 16; // 物理缓存的MEM片数(4 | 8 | 16 | 32 | 64 | 128)
	parameter integer CBUF_DEPTH_FOREACH_BANK = 512; // 物理缓存每片MEM的深度(128 | 256 | 512 | 1024 | 2048 | 4096 | 8192)
	parameter integer MAX_FMBUF_ROWN = 512; // 特征图缓存的最大表面行数(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
	parameter integer RBUF_BANK_N = 8; // 中间结果缓存MEM个数(>=2)
	parameter integer RBUF_DEPTH = 512; // 中间结果缓存MEM深度(16 | ...)
**/

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#include "sd_card_fatfs.h"
#include "axi_generic_pool.h"

#include "xparameters.h"
#include "xil_cache.h"

#include <stdio.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define IN_FMAP_FILENAME "in_fmap_max_0.bin" // 输入特征图文件名
#define OUT_FMAP_FILENAME "out_fmap_max_0.bin" // 输出特征图文件名

#define IN_FMAP_LEN 640 * 640 * 16 // 输入特征图数据总量
#define OUT_FMAP_LEN 320 * 320 * 16 // 输出特征图数据总量

#define OUT_FMAP_ROW_N 320 * 2 // 输出特征图表面行总数

#define IN_DATA_LEN 2 // 输入特征图的数据大小
#define OUT_DATA_LEN 4 // 输出特征图的数据大小

// #define TO_FLUSH_DCACHE // 是否需要刷新DCache

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static FATFS fatfs; // FAT32文件系统
static FIL file_handler; // 文件描述符

static AxiGnrPoolHandler axi_generic_pool; // 通用池化处理单元
static AxiGnrPoolPerfMonsts pm_sts; // 性能监测状态

static uint16_t in_fmap[IN_FMAP_LEN]; // 输入特征图(数组)
static float out_fmap[OUT_FMAP_LEN]; // 输出特征图(数组)

////////////////////////////////////////////////////////////////////////////////////////////////////////////

int main(){
	// 初始化SD卡文件系统
	if(init_sd_card_fatfs(&fatfs, 0)){
		return -1;
	}

	// 从SD卡读取输入特征图
	if(sd_card_fatfs_fopen(&file_handler, IN_FMAP_FILENAME, FA_READ, 0)){
		return -1;
	}

	if(sd_card_fatfs_fread(&file_handler, (void*)in_fmap, IN_FMAP_LEN * IN_DATA_LEN) != IN_FMAP_LEN * IN_DATA_LEN){
		return -1;
	}
	if(sd_card_fatfs_fclose(&file_handler)){
		return -1;
	}

	// 初始化通用池化处理单元
	if(axi_generic_pool_init(&axi_generic_pool, XPAR_AXI_GENERIC_POOL_0_BASEADDR)){
		return -1;
	}

	// 配置上采样层参数
	AxiGnrPoolFmapCfg fmap_cfg;
	AxiGnrPoolBufferCfg buffer_cfg;
	AxiGnrPoolPoolModeCfg cal_cfg;

	fmap_cfg.ifmap_baseaddr = (uint8_t*)in_fmap;
	fmap_cfg.ofmap_baseaddr = (uint8_t*)out_fmap;
	fmap_cfg.ifmap_w = 640;
	fmap_cfg.ifmap_h = 640;
	fmap_cfg.ifmap_c = 16;
	fmap_cfg.external_padding_left = 0;
	fmap_cfg.external_padding_right = 0;
	fmap_cfg.external_padding_top = 0;
	fmap_cfg.external_padding_bottom = 0;
	fmap_cfg.ofmap_data_type = POOL_O_4_BYTE;

	buffer_cfg.fmbufcoln = POOL_COLN_1024;

	cal_cfg.cal_fmt = POOL_FP16;
	cal_cfg.horizontal_stride = 2;
	cal_cfg.vertical_stride = 2;
	cal_cfg.pool_window_w = 2;
	cal_cfg.pool_window_h = 2;
	cal_cfg.use_post_mac = 0;

	if(axi_generic_pool_cfg_in_pool_mode(
		&axi_generic_pool,
		PROC_MODE_MAX,
		(const AxiGnrPoolFmapCfg*)&fmap_cfg,
		(const AxiGnrPoolBufferCfg*)&buffer_cfg,
		(const AxiGnrPoolPoolModeCfg*)&cal_cfg)
	){
		return -1;
	}

#ifdef TO_FLUSH_DCACHE
	// 刷新DCache
	Xil_DCacheFlushRange((INTPTR)in_fmap, IN_FMAP_LEN * IN_DATA_LEN);
#endif

	// 启动通用池化处理单元
	if(axi_generic_pool_enable_cal_sub_sys(&axi_generic_pool)){
		return -1;
	}

	if(axi_generic_pool_start(&axi_generic_pool)){
		return -1;
	}

	// 使能性能监测计数器
	if(axi_generic_pool_enable_pm_cnt(&axi_generic_pool)){
		return -1;
	}

	// 等待通用池化处理单元的数据输出完成
	while(axi_generic_pool_get_cmd_fns_n(&axi_generic_pool, Q_CMD_FNS_N_S2MM) < OUT_FMAP_ROW_N);

	// 获取性能监测计数器的值
	if(axi_generic_pool_get_pm_cnt(&axi_generic_pool, &pm_sts)){
		return -1;
	}
	printf("pm_cnt = %d\r\n", (int)pm_sts.cycle_n);

	// 除能计算子系统
	axi_generic_pool_disable_cal_sub_sys(&axi_generic_pool);
	// 除能性能监测计数器
	axi_generic_pool_disable_pm_cnt(&axi_generic_pool);

	// 清除DMA命令完成数
	if(axi_generic_pool_clr_cmd_fns_n(&axi_generic_pool, C_ALL)){
		return -1;
	}
	// 清除性能监测计数器
	if(axi_generic_pool_clr_pm_cnt(&axi_generic_pool)){
		return -1;
	}

#ifdef TO_FLUSH_DCACHE
	// 刷新DCache
	Xil_DCacheFlushRange((INTPTR)out_fmap, OUT_FMAP_LEN * OUT_DATA_LEN);
#endif

	// 向SD卡写入输出特征图
	if(sd_card_fatfs_fopen(&file_handler, OUT_FMAP_FILENAME, FA_WRITE | FA_CREATE_ALWAYS, 0)){
		return -1;
	}

	if(sd_card_fatfs_fwrite(&file_handler, (void*)out_fmap, OUT_FMAP_LEN * OUT_DATA_LEN) != OUT_FMAP_LEN * OUT_DATA_LEN){
		return -1;
	}

	if(sd_card_fatfs_fclose(&file_handler)){
		return -1;
	}

	while(1);
}
