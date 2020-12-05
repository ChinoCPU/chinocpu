`include "defines.v"

module pc_reg(

	input wire										clk,
	input wire										rst,
	input wire[5:0]									stall,

	output reg[`InstAddrBus]						pc,
	output reg                    					ce,

	input wire										branch_flag_i,
	input wire[`RegBus]								target_addr_i
	
);
	parameter  RUN_N_INST = 4;
	reg [5:0]	cnt;
	always @ (posedge clk) begin
		if (ce == `ChipDisable) begin
			pc <= `ZeroWord;
		end else if (stall[0] == `NoStop) begin
			if (branch_flag_i == `Branch)
				pc <= target_addr_i;
			else
	 			pc <= pc + 8;
		end
	end
	
	always @ (posedge clk) begin
		if (rst == `RstEnable) begin
			ce <= `ChipDisable;
		end else begin
				ce <= `ChipEnable;
		end
	end

endmodule