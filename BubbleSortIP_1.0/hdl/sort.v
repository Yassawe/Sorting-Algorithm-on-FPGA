`timescale 1ns / 1ps

module sort(
    input clock,
    input reset,
    input start,
    input writeEnable,
    input [31:0] inputArray,
    input readEnable,
    output [31:0] SortedArray,
    output reg allDoneFlag
    );
    
    //variables to interact with RAM
    wire [31:0] inputDataA; 
    wire [31:0] outputDataA;
    wire [31:0] inputDataB;
    wire [31:0] outputDataB;
    wire writeEnableA;
    wire writeEnableB;
    wire [9:0] addressA; 
    wire [9:0] addressB; 

    
    // variables used during sort operation
    reg [31:0] inputSortA;
    reg [31:0] inputSortB;
    reg [9:0] addressSortA;
    reg [9:0] addressSortB;
    reg writeEnableSortA;
    reg writeEnableSortB;
    
    
    // pointers for sorting 
    reg [9:0] i, j; 
    reg [9:0] N; // pointer to the last element of the array, length-1
    reg swapFlag; // if there were no swaps in one iteration, sorting is done and no need to continue
    reg sortDone; //array is sorted and is in RAM
    reg storeDone; // sorted array is transferred to FIFO
    
    // port A used for writing and for sorting
    reg [9:0] writeAddress;
    assign inputDataA = (writeEnable) ? (inputArray) : (inputSortA);
    assign writeEnableA = (writeEnable) ? (writeEnable) : (writeEnableSortA);
    assign addressA = (writeEnable) ? (writeAddress) : (addressSortA);

    // port B used for reading and for sorting
    reg [9:0] readAddress;
    assign inputDataB = inputSortB;
    assign writeEnableB = writeEnableSortB;
    assign addressB = (sortDone) ? (readAddress) : (addressSortB);
    
    // I need 0 read latency from output in order to reliably read from processor, so I use FIFO to store sorted array
    reg FIFOWriteEnable;
    
    reg [2:0] state;
    localparam IDLE='b000,
               OUTERLOOP='b001,
               INNERLOOP='b010,
               FETCH='b011,
               COMPARE='b100,
               STORE='b101,
               DONE='b111;
    
    //always block for external write logic
    always @(posedge clock)
    begin
        if (reset)
            begin
                writeAddress<=0;
                N<=0;
            end
        else if(allDoneFlag) //if everything is done, module is ready to recieve new array, without reset
           begin
                writeAddress<=0;
                N<=0;
           end
        else if (writeEnable)
            begin
                writeAddress<=writeAddress+1;
                N<=writeAddress; // N will store the last address, i.e. length-1
            end
    end 
    
    
    //always block for storing already sorted array in FIFO
    always @(posedge clock)
        if(reset)
            begin
                readAddress<=0;
                FIFOWriteEnable<=0;
                storeDone<=0;
            end
        else if (allDoneFlag) // if all is done, sorted array is already in FIFO, module is ready to recieve new array
            begin
                   readAddress<=0;
                   FIFOWriteEnable<=0;
                   storeDone<=0;
            end
        else if (sortDone)
            begin
                readAddress<=readAddress+1;
                if(readAddress<=N)
                   begin
                        FIFOWriteEnable<=1;
                   end 
                else
                   begin
                        FIFOWriteEnable<=0;
                        storeDone<=1;
                   end
            end
        
    //always block for FSM
    always @(posedge clock)
    begin
        if (reset)
            begin
                state<=IDLE;
                inputSortA<=0;
                inputSortB<=0;
                writeEnableSortA<=0;
                writeEnableSortB<=0;
                addressSortA<=0;
                addressSortB<=0;
                i<=0;
                j<=0;
                allDoneFlag<=0;
                sortDone<=0;
                swapFlag<=1;         
            end
       else
            begin
                 case (state)
                        IDLE: begin
                              if(start)
                                begin
                                    state<=OUTERLOOP;
                                    i<=0;
                                end
                        end
                        
                        OUTERLOOP: begin
                                   if(!swapFlag)
                                        begin
                                            state<=STORE;
                                            sortDone<=1;
                                        end
                                   else if (i==N)
                                        begin
                                            state<=STORE;
                                            sortDone<=1;
                                        end
                                   else
                                        begin
                                            j<=0;
                                            swapFlag<=0;
                                            state<=INNERLOOP;
                                        end
                        end
                        
                        INNERLOOP: begin
                                writeEnableSortA<=0;
                                writeEnableSortB<=0;
                                if (j==N-i)
                                    begin
                                        i<=i+1;
                                        state<=OUTERLOOP;
                                    end
                                else
                                    begin
                                        addressSortA<=j;
                                        addressSortB<=j+1;
                                        state<=FETCH; 
                                    end
                        end
                        
                        FETCH: begin // respecting 1 clock read latency of RAM block
                            state<=COMPARE; 
                        end
                        
                        COMPARE: begin
                               if (outputDataA>outputDataB)
                                    begin
                                        inputSortA<=outputDataB; //SWAP
                                        inputSortB<=outputDataA;
                                        writeEnableSortA<=1;
                                        writeEnableSortB<=1;
                                        swapFlag<=1;
                                    end
                                j<=j+1;
                                state<=INNERLOOP;
                        end
                        
                        STORE: begin
                            if(storeDone)
                               state<=DONE;                              
                        end
                        
                        DONE: begin
                        allDoneFlag<=1;
                        inputSortA<=0;
                        inputSortB<=0;
                        writeEnableSortA<=0;
                        writeEnableSortB<=0;
                        addressSortA<=0;
                        addressSortB<=0;
                        i<=0;
                        j<=0;
                        sortDone<=0;
                        swapFlag<=1;
                        if (!start)
                            begin
                                allDoneFlag<=0;
                                state<=IDLE;
                            end          
                        end
                 endcase
            end
    end
    
    blk_mem_gen_0 DualRAM (
      .clka(clock),    // input wire clka
      .wea(writeEnableA),      // input wire [0 : 0] wea
      .addra(addressA),  // input wire [9 : 0] addra
      .dina(inputDataA),    // input wire [31 : 0] dina
      .douta(outputDataA),  // output wire [31 : 0] douta
      .clkb(clock),    // input wire clkb
      .web(writeEnableB),      // input wire [0 : 0] web
      .addrb(addressB),  // input wire [9 : 0] addrb
      .dinb(inputDataB),    // input wire [31 : 0] dinb
      .doutb(outputDataB)  // output wire [31 : 0] doutb
    );
    
    // I store sorted array in FIFO, because it has read latency of 0
    fifo_generator_0 sortedArrayFIFO (
      .clk(clock),      // input wire clk
      .srst(reset),    // input wire srst
      .din(outputDataB),      // input wire [31 : 0] din
      .wr_en(FIFOWriteEnable),  // input wire wr_en
      .rd_en(readEnable),  // input wire rd_en
      .dout(SortedArray),    // output wire [31 : 0] dout
      .full(),    // output wire full
      .empty()  // output wire empty
    );
endmodule
