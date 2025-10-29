`timescale 1ns / 1ps

`ifndef __SCB_H

`define __SCB_H

`include "transactions.sv"
`include "utils.sv"

`uvm_analysis_imp_decl(_strm)
`uvm_analysis_imp_decl(_sfc)

/** 计分板:特征图/卷积核表面生成单元 **/
class ConvDataSfcGenScb #(
	integer STREAM_DATA_WIDTH = 32, // 特征图/卷积核数据流的数据位宽(32 | 64 | 128 | 256)
	integer ATOMIC_C = 4, // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	integer EXTRA_DATA_WIDTH = 4 // 随路传输附加数据的位宽(必须>=1)
)extends uvm_scoreboard;
	
	local int strm_pkt_fid;
	local int sfc_pkt_fid;
	
	uvm_analysis_imp_strm #(AXISTrans #(.data_width(STREAM_DATA_WIDTH), 
		.user_width(5+EXTRA_DATA_WIDTH)), ConvDataSfcGenScb) strm_imp;
	uvm_analysis_imp_sfc #(AXISTrans #(.data_width(ATOMIC_C*2*8), 
		.user_width(EXTRA_DATA_WIDTH)), ConvDataSfcGenScb) sfc_imp;
	
	local FmapKwgtPktBaseTrans strm_pkt_tr_fifo[$];
	local FmapKwgtPktBaseTrans sfc_pkt_tr_fifo[$];
	
	// 注册component
	`uvm_component_param_utils(ConvDataSfcGenScb #(.STREAM_DATA_WIDTH(STREAM_DATA_WIDTH), .ATOMIC_C(ATOMIC_C), .EXTRA_DATA_WIDTH(EXTRA_DATA_WIDTH)))
	
	function new(string name = "ConvDataSfcGenScb", uvm_component parent = null);
		super.new(name, parent);
	endfunction
	
	function void write_strm(AXISTrans #(.data_width(STREAM_DATA_WIDTH), .user_width(5+EXTRA_DATA_WIDTH)) tr);
		automatic FmapKwgtPktTrans #(.HAS_VLD_DATA_N_FIELD(1'b1), 
			.STREAM_DATA_WIDTH(STREAM_DATA_WIDTH), .EXTRA_DATA_WIDTH(EXTRA_DATA_WIDTH)) strm_pkt_tr;
		
		strm_pkt_tr = new(tr, "FmapKwgtStrmPktTrans");
		
		`__PRINTER_SET_MCD(uvm_default_printer, this.strm_pkt_fid);
		strm_pkt_tr.print();
		`__PRINTER_SET_MCD(uvm_default_printer, UVM_STDOUT);
		
		this.strm_pkt_tr_fifo.push_back(strm_pkt_tr);
	endfunction
	
	function void write_sfc(AXISTrans #(.data_width(ATOMIC_C*2*8), .user_width(EXTRA_DATA_WIDTH)) tr);
		automatic FmapKwgtPktTrans #(.HAS_VLD_DATA_N_FIELD(1'b0), 
			.STREAM_DATA_WIDTH(ATOMIC_C*2*8), .EXTRA_DATA_WIDTH(EXTRA_DATA_WIDTH)) sfc_pkt_tr;
		
		sfc_pkt_tr = new(tr, "FmapKwgtSfcPktTrans");
		
		`__PRINTER_SET_MCD(uvm_default_printer, this.sfc_pkt_fid);
		sfc_pkt_tr.print();
		`__PRINTER_SET_MCD(uvm_default_printer, UVM_STDOUT);
		
		this.sfc_pkt_tr_fifo.push_back(sfc_pkt_tr);
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.strm_pkt_fid = $fopen("strm.txt", "w");
		this.sfc_pkt_fid = $fopen("sfc.txt", "w");
		
		// 创建通信端口
		this.strm_imp = new("strm_imp", this);
		this.sfc_imp = new("sfc_imp", this);
	endfunction
	
	virtual task main_phase(uvm_phase phase);
		automatic int cmp_id = 0;
		
		super.main_phase(phase);
		
		forever
		begin
			automatic FmapKwgtPktBaseTrans strm_pkt_tr_to_cmp;
			automatic FmapKwgtPktBaseTrans sfc_pkt_tr_to_cmp;
			
			wait((this.strm_pkt_tr_fifo.size() > 0) && (this.sfc_pkt_tr_fifo.size() > 0));
			
			strm_pkt_tr_to_cmp = this.strm_pkt_tr_fifo.pop_front();
			sfc_pkt_tr_to_cmp = this.sfc_pkt_tr_fifo.pop_front();
			
			if(strm_pkt_tr_to_cmp.compare(sfc_pkt_tr_to_cmp))
				`uvm_info("ConvDataSfcGenScb", $sformatf("[%0d] cmp matched!", cmp_id), UVM_LOW)
			else
				`uvm_error("ConvDataSfcGenScb", $sformatf("[%0d] cmp mismatched!", cmp_id))
			
			cmp_id++;
		end
	endtask
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		$fclose(this.strm_pkt_fid);
		$fclose(this.sfc_pkt_fid);
	endfunction
	
endclass
	
`endif
