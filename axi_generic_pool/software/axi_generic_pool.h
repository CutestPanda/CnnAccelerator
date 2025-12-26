/************************************************************************************************************************
通用池化处理单元驱动(接口头文件)
@brief  提供了通用池化处理单元的初始化、控制、状态获取、配置等API
               配置分为池化和上采样模式
@date   2025/12/17
@author 陈家耀
@eidt   2025.12.17 1.00 创建了第1个正式版本
        2025.12.24 1.01 修复BUG: 向buf_cfg0寄存器的[31:16]应写入"特征图缓存可缓存的表面行数 - 1"
        2025.12.22 1.02 增加性能监测计数器组(运行周期数, MM2S通道传输字节数, S2MM通道传输字节数, 更新单元组运行周期数)
        2025.12.22 1.10 为最大池化增加非0常量填充模式
        2025.12.26 1.11 修改ctrl0寄存器
************************************************************************************************************************/

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 枚举类型: DMA命令完成数查询类别
typedef enum{
	POOL_Q_CMD_FNS_N_MM2S,
	POOL_Q_CMD_FNS_N_S2MM
}AxiGnrPoolCmdFnsNQueryType;

// 枚举类型: DMA命令完成数(计数器)清除类别
typedef enum{
	POOL_C_CMD_FNS_N_MM2S,
	POOL_C_CMD_FNS_N_S2MM,
	POOL_C_ALL
}AxiGnrPoolCmdFnsNClrType;

// 枚举类型: 处理模式
typedef enum{
	PROC_MODE_AVG = 0, // 平均池化
	PROC_MODE_MAX = 1, // 最大池化
	PROC_MODE_UPSP = 2 // 上采样
}AxiGnrPoolProcMode;

// 枚举类型: 运算数据格式
typedef enum{
	POOL_INT8 = 0,
	POOL_INT16 = 1,
	POOL_FP16 = 2
}AxiGnrPoolCalFmt;

// 枚举类型: 输出特征图数据格式
typedef enum{
	POOL_O_1_BYTE = 0,
	POOL_O_2_BYTE = 1,
	POOL_O_4_BYTE = 2
}AxiGnrPoolOfmapDataType;

// 枚举类型: 特征图缓存表面行长度
typedef enum{
	POOL_COLN_4 = 0b0000,
	POOL_COLN_8 = 0b0001,
	POOL_COLN_16 = 0b0010,
	POOL_COLN_32 = 0b0011,
	POOL_COLN_64 = 0b0100,
	POOL_COLN_128 = 0b0101,
	POOL_COLN_256 = 0b0110,
	POOL_COLN_512 = 0b0111,
	POOL_COLN_1024 = 0b1000,
	POOL_COLN_2048 = 0b1001,
	POOL_COLN_4096 = 0b1010
}AxiGnrPoolFmbufColnType;

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 结构体: 加速器属性
typedef struct{
	char version[9]; // 版本号
	char accelerator_type[7]; // 加速器类型
	uint8_t accelerator_id; // 加速器ID

	uint8_t max_pool_supported; // 是否支持最大池化
	uint8_t avg_pool_supported; // 是否支持平均池化
	uint8_t up_sample_supported; // 是否支持上采样
	uint8_t int8_supported; // 是否支持INT8运算数据格式
	uint8_t int16_supported; // 是否支持INT16运算数据格式
	uint8_t fp16_supported; // 是否支持FP16运算数据格式
	uint8_t post_mac_supported; // 是否支持后乘加处理
	uint8_t ext_padding_supported; // 是否支持外填充
	uint8_t non_zero_const_padding_supported; // 是否支持非零常量填充
	uint8_t performance_monitor_supported; // 是否支持性能监测

	uint8_t atomic_c; // 通道并行数
	uint8_t post_mac_prl_n; // 后乘加并行数

	uint16_t mm2s_stream_data_width; // MM2S通道DMA数据流的位宽
	uint16_t s2mm_stream_data_width; // S2MM通道DMA数据流的位宽

	uint16_t phy_buf_bank_n; // 物理缓存BANK数
	uint16_t phy_buf_bank_depth; // 物理缓存BANK深度
	uint16_t max_fmbuf_row_n; // 特征图缓存最大表面行数
	uint16_t mid_res_buf_bank_n; // 中间结果缓存BANK数
	uint16_t mid_res_buf_bank_depth; // 中间结果缓存BANK深度
}AxiGnrPoolProp;

// 结构体: 寄存器域(属性)
typedef struct{
	uint32_t version;
	uint32_t acc_name;
	uint32_t info0;
	uint32_t info1;
	uint32_t info2;
	uint32_t info3;
}AxiGnrPoolRegRgnProp;

// 结构体: 寄存器域(控制)
typedef struct{
	uint32_t ctrl0;
}AxiGnrPoolRegRgnCtrl;

// 结构体: 寄存器域(状态)
typedef struct{
	uint32_t sts0;
	uint32_t sts1;
	uint32_t sts2;
	uint32_t sts3;
	uint32_t sts4;
	uint32_t sts5;
	uint32_t sts6;
}AxiGnrPoolRegRgnSts;

// 结构体: 寄存器域(计算配置)
typedef struct{
	uint32_t cal_cfg0;
	uint32_t cal_cfg1;
	uint32_t cal_cfg2;
	uint32_t cal_cfg3;
	uint32_t cal_cfg4;
	uint32_t cal_cfg5;
}AxiGnrPoolRegRgnCalCfg;

// 结构体: 寄存器域(特征图配置)
typedef struct{
	uint32_t fmap_cfg0;
	uint32_t fmap_cfg1;
	uint32_t fmap_cfg2;
	uint32_t fmap_cfg3;
	uint32_t fmap_cfg4;
	uint32_t fmap_cfg5;
	uint32_t fmap_cfg6;
}AxiGnrPoolRegRgnFmapCfg;

// 结构体: 寄存器域(缓存配置)
typedef struct{
	uint32_t buf_cfg0;
	uint32_t buf_cfg1;
}AxiGnrPoolRegRgnBufCfg;

// 结构体: 特征图参数配置
typedef struct{
	uint8_t* ifmap_baseaddr; // 输入特征图基地址
	uint8_t* ofmap_baseaddr; // 输出特征图基地址

	uint16_t ifmap_w; // 输入特征图宽度
	uint16_t ifmap_h; // 输入特征图高度
	uint16_t ifmap_c; // 特征图通道数

	uint8_t external_padding_left; // 特征图左部外填充数
	uint8_t external_padding_right; // 特征图右部外填充数
	uint8_t external_padding_top; // 特征图上部外填充数
	uint8_t external_padding_bottom; // 特征图下部外填充数

	AxiGnrPoolOfmapDataType ofmap_data_type; // 输出特征图数据大小类型
}AxiGnrPoolFmapCfg;

// 结构体: 缓存参数配置
typedef struct{
	AxiGnrPoolFmbufColnType fmbufcoln; // 特征图缓存每个表面行的表面个数类型
}AxiGnrPoolBufferCfg;

// 结构体: 池化参数配置
typedef struct{
	AxiGnrPoolCalFmt cal_fmt; // 运算数据格式

	uint8_t horizontal_stride; // 池化水平步长
	uint8_t vertical_stride; // 池化垂直步长
	uint8_t pool_window_w; // 池化窗口宽度
	uint8_t pool_window_h; // 池化窗口高度

	uint8_t non_zero_const_padding_mode; // 是否处于非0常量填充模式
	uint16_t const_to_fill; // 待填充的常量

	uint8_t use_post_mac; // 是否启用后乘加处理
	uint8_t post_mac_is_a_eq_1; // 后乘加处理的参数A的实际值是否为1
	uint8_t post_mac_is_b_eq_0; // 后乘加处理的参数B的实际值是否为0
	uint8_t post_mac_fixed_point_quat_accrc; // 后乘加处理的定点数量化精度
	uint32_t post_mac_param_a; // 后乘加处理的参数A
	uint32_t post_mac_param_b; // 后乘加处理的参数B
}AxiGnrPoolPoolModeCfg;

// 结构体: 上采样参数配置
typedef struct{
	AxiGnrPoolCalFmt cal_fmt; // 运算数据格式

	uint8_t upsample_horizontal_n; // 上采样水平复制量
	uint8_t upsample_vertical_n; // 上采样垂直复制量

	uint8_t non_zero_const_padding_mode; // 是否处于非0常量填充模式
	uint16_t const_to_fill; // 待填充的常量

	uint8_t use_post_mac; // 是否启用后乘加处理
	uint8_t post_mac_is_a_eq_1; // 后乘加处理的参数A的实际值是否为1
	uint8_t post_mac_is_b_eq_0; // 后乘加处理的参数B的实际值是否为0
	uint8_t post_mac_fixed_point_quat_accrc; // 后乘加处理的定点数量化精度
	uint32_t post_mac_param_a; // 后乘加处理的参数A
	uint32_t post_mac_param_b; // 后乘加处理的参数B
}AxiGnrPoolUpsModeCfg;

// 结构体: 性能监测状态
typedef struct{
	uint32_t cycle_n; // 运行周期数
	uint32_t mm2s_tsf_n; // MM2S通道传输字节数
	uint32_t s2mm_tsf_n; // S2MM通道传输字节数
	uint32_t upd_grp_run_n; // 更新单元组运行周期数
}AxiGnrPoolPerfMonsts;

// 结构体: 通用池化处理单元
typedef struct{
	uint32_t* reg_base_ptr; // 寄存器区基地址

	// 寄存器域
	AxiGnrPoolRegRgnProp* reg_region_prop; // 寄存器域(属性)
	AxiGnrPoolRegRgnCtrl* reg_region_ctrl; // 寄存器域(控制)
	AxiGnrPoolRegRgnSts* reg_region_sts; // 寄存器域(状态)
	AxiGnrPoolRegRgnCalCfg* reg_region_cal_cfg; // 寄存器域(计算配置)
	AxiGnrPoolRegRgnFmapCfg* reg_region_fmap_cfg; // 寄存器域(特征图配置)
	AxiGnrPoolRegRgnBufCfg* reg_region_buffer_cfg; // 寄存器域(缓存配置)

	AxiGnrPoolProp property; // 加速器属性
}AxiGnrPoolHandler;

////////////////////////////////////////////////////////////////////////////////////////////////////////////

int axi_generic_pool_init(AxiGnrPoolHandler* handler, uint32_t baseaddr); // 初始化通用池化处理单元

int axi_generic_pool_enable(AxiGnrPoolHandler* handler); // 使能加速器
void axi_generic_pool_disable(AxiGnrPoolHandler* handler); // 除能加速器
int axi_generic_pool_enable_cal_sub_sys(AxiGnrPoolHandler* handler); // 使能计算子系统
void axi_generic_pool_disable_cal_sub_sys(AxiGnrPoolHandler* handler); // 除能计算子系统
int axi_generic_pool_enable_pm_cnt(AxiGnrPoolHandler* handler); // 使能性能监测计数器
void axi_generic_pool_disable_pm_cnt(AxiGnrPoolHandler* handler); // 除能性能监测计数器
int axi_generic_pool_start(AxiGnrPoolHandler* handler); // 启动通用池化处理单元
uint8_t axi_generic_pool_is_busy(AxiGnrPoolHandler* handler); // 判断通用池化处理单元是否忙碌

// 以池化模式配置通用池化处理单元
int axi_generic_pool_cfg_in_pool_mode(
	AxiGnrPoolHandler* handler,
	AxiGnrPoolProcMode mode,
	const AxiGnrPoolFmapCfg* fmap_cfg, const AxiGnrPoolBufferCfg* buffer_cfg, const AxiGnrPoolPoolModeCfg* cal_cfg
);

// 以上采样模式配置通用池化处理单元
int axi_generic_pool_cfg_in_up_sample_mode(
	AxiGnrPoolHandler* handler,
	const AxiGnrPoolFmapCfg* fmap_cfg, const AxiGnrPoolBufferCfg* buffer_cfg, const AxiGnrPoolUpsModeCfg* cal_cfg
);

uint32_t axi_generic_pool_get_cmd_fns_n(AxiGnrPoolHandler* handler, AxiGnrPoolCmdFnsNQueryType query_type); // 查询DMA命令完成数
int axi_generic_pool_clr_cmd_fns_n(AxiGnrPoolHandler* handler, AxiGnrPoolCmdFnsNClrType clr_type); // 清除DMA命令完成数计数器
int axi_generic_pool_get_pm_cnt(AxiGnrPoolHandler* handler, AxiGnrPoolPerfMonsts* pm_sts); // 获取性能监测计数器的值
int axi_generic_pool_clr_pm_cnt(AxiGnrPoolHandler* handler); // 清除性能监测计数器
