///////////////////////////////////////////
// busfsm.sv
//
// Written: Ross Thompson ross1728@gmail.com December 29, 2021
// Modified: 
//
// Purpose: Load/Store Unit's interface to BUS for cacheless system
// 
// A component of the Wally configurable RISC-V project.
// 
// Copyright (C) 2021 Harvey Mudd College & Oklahoma State University
//
// MIT LICENSE
// Permission is hereby granted, free of charge, to any person obtaining a copy of this 
// software and associated documentation files (the "Software"), to deal in the Software 
// without restriction, including without limitation the rights to use, copy, modify, merge, 
// publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons 
// to whom the Software is furnished to do so, subject to the following conditions:
//
//   The above copyright notice and this permission notice shall be included in all copies or 
//   substantial portions of the Software.
//
//   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, 
//   INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR 
//   PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS 
//   BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, 
//   TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE 
//   OR OTHER DEALINGS IN THE SOFTWARE.
////////////////////////////////////////////////////////////////////////////////////////////////

`include "wally-config.vh"


module busfsm #(parameter integer LOGWPL)
  (input logic               clk,
   input logic               reset,

   input logic [1:0]         RW,
   input logic               BusAck,
   input logic               BusInit, // This might be better as LSUBusLock, or to send this using BusAck.
   input logic               CPUBusy,

   output logic              BusStall,
   output logic              BusWrite,
   output logic              BusRead,
   output logic [1:0]        HTRANS,
   output logic              BusCommitted
);
  
  typedef enum logic [2:0] {STATE_BUS_READY,
				STATE_BUS_UNCACHED_WRITE,
				STATE_BUS_UNCACHED_WRITE_DONE,
				STATE_BUS_UNCACHED_READ,
				STATE_BUS_UNCACHED_READ_DONE,
				STATE_BUS_CPU_BUSY} busstatetype;

  typedef enum logic [1:0] {AHB_IDLE = 2'b00, AHB_BUSY = 2'b01, AHB_NONSEQ = 2'b10, AHB_SEQ = 2'b11} ahbtranstype;

  (* mark_debug = "true" *) busstatetype BusCurrState, BusNextState;

  always_ff @(posedge clk)
    if (reset)    BusCurrState <= #1 STATE_BUS_READY;
    else BusCurrState <= #1 BusNextState;  
  
  always_comb begin
	case(BusCurrState)
	  STATE_BUS_READY:               if(RW[0])                BusNextState = STATE_BUS_UNCACHED_WRITE;
		                             else if(RW[1])                BusNextState = STATE_BUS_UNCACHED_READ;
                                     else                          BusNextState = STATE_BUS_READY;
      STATE_BUS_UNCACHED_WRITE:      if(BusAck)                    BusNextState = STATE_BUS_UNCACHED_WRITE_DONE;
		                             else                          BusNextState = STATE_BUS_UNCACHED_WRITE;
      STATE_BUS_UNCACHED_READ:       if(BusAck)                    BusNextState = STATE_BUS_UNCACHED_READ_DONE;
		                             else                          BusNextState = STATE_BUS_UNCACHED_READ;
      STATE_BUS_UNCACHED_WRITE_DONE: if(CPUBusy)                   BusNextState = STATE_BUS_CPU_BUSY;
                                     else                          BusNextState = STATE_BUS_READY;
      STATE_BUS_UNCACHED_READ_DONE:  if(CPUBusy)                   BusNextState = STATE_BUS_CPU_BUSY;
                                     else                          BusNextState = STATE_BUS_READY;
	  STATE_BUS_CPU_BUSY:            if(CPUBusy)                   BusNextState = STATE_BUS_CPU_BUSY;
                                     else                          BusNextState = STATE_BUS_READY;
	  default:                                                     BusNextState = STATE_BUS_READY;
	endcase
  end

  assign BusStall = (BusCurrState == STATE_BUS_READY & |RW) |
					(BusCurrState == STATE_BUS_UNCACHED_WRITE) |
					(BusCurrState == STATE_BUS_UNCACHED_READ);
  assign BusWrite = (BusCurrState == STATE_BUS_READY & RW[0]) |
							   (BusCurrState == STATE_BUS_UNCACHED_WRITE);
  assign BusRead = (BusCurrState == STATE_BUS_READY & RW[1]) |
							  (BusCurrState == STATE_BUS_UNCACHED_READ);
  assign BusCommitted = BusCurrState != STATE_BUS_READY;

  assign HTRANS = (BusRead | BusWrite) & (~BusAck) ? AHB_NONSEQ : AHB_IDLE; 
endmodule
