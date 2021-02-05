`include "defines.v"

module id_ex(

	input	wire					clk,
	input wire						rst,

	
	//从译码阶段传递的信息
	input wire[`AluOpBus]         	id_aluop,
	input wire[`AluSelBus]        	id_alusel,
	input wire[`RegBus]           	id_reg1,
	input wire[`RegBus]           	id_reg2,
	input wire[`RegAddrBus]       	id_wd,
	input wire                    	id_wreg,	
	input wire[5:0]					stall,
	input wire 						next_inst_in_delayslot_i,
	input wire 						id_is_delayslot_i,
	input wire[`RegBus]				id_offset,
	input wire[`InstBus]			id_inst,
	//传递到执行阶段的信息
	output reg[`AluOpBus]         	ex_aluop,
	output reg[`AluSelBus]        	ex_alusel,
	output reg[`RegBus]           	ex_reg1,
	output reg[`RegBus]           	ex_reg2,
	output reg[`RegAddrBus]       	ex_wd,
	output reg                    	ex_wreg,
	output reg						is_delayslot_o,
	output reg 						ex_is_in_delayslot_o,
	output reg[`RegBus]				ex_offset,
	output reg[`InstBus]			ex_inst
);

	always @ (posedge clk) begin
		if (rst == `RstEnable) begin
			ex_aluop <= `EXE_NOP_OP;
			ex_alusel <= `EXE_RES_NOP;
			ex_reg1 <= `ZeroWord;
			ex_reg2 <= `ZeroWord;
			ex_wd <= `NOPRegAddr;
			ex_wreg <= `WriteDisable;
			ex_inst <= `ZeroDoubleWord;
		end else if (stall[2] == `Stop && stall[3] == `NoStop) begin
			ex_aluop <= ex_aluop;
			ex_alusel <= ex_alusel;
			ex_reg1 <= ex_reg1;
			ex_reg2 <= ex_reg2;
			ex_wd <= `NOPRegAddr;
			ex_wreg <= `WriteDisable;
			ex_is_in_delayslot_o <= `NotInDelaySlot;
			ex_inst <= `ZeroDoubleWord;
		end else if (stall[2] == `NoStop) begin		
			ex_aluop <= id_aluop;
			ex_alusel <= id_alusel;
			ex_reg1 <= id_reg1;
			ex_reg2 <= id_reg2;
			ex_wd <= id_wd;
			ex_wreg <= id_wreg;	
			ex_offset <= id_offset;	
			is_delayslot_o <= next_inst_in_delayslot_i;
			ex_is_in_delayslot_o <= id_is_delayslot_i;
			ex_inst <= id_inst;
		end
	end
	
endmodule