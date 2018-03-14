#include <stdio.h>
#include "bingo_card_sim_data.h"

#define MAX_NUMBER_CALL 32

#define AlignByteSizeBy(TotalBytes, AlignLength) ((TotalBytes) += ((TotalBytes) % (AlignLength)))

//NOTE(gerald): Reference from "https://en.wikipedia.org/wiki/Xorshift"
__device__ u32
XorShift32(u32 State)
{
    u32 Result = State;
    Result ^= Result << 13;
    Result ^= Result >> 17;
    Result ^= Result << 5;
//    State = Result;
    return Result;
}


__global__ void
LoadNumbersToBeCalled(numbers_load_memory_block GlobalData)
{
    extern __shared__ u8 SliceData[];

    u32 threadID = (blockIdx.x * blockDim.x) + threadIdx.x;
    u32 numberIndex = threadID % MAX_NUMBER_CALL;
    u32 SliceIndex = threadIdx.x / MAX_NUMBER_CALL;
    if(numberIndex == 0)
    {
        //StartNumber for this slice
        SliceData[SliceIndex * 2] = 1 + (XorShift32(threadID+1) % GlobalData.MaxNumbers);
        //IncrementNumber for this slice
        SliceData[(SliceIndex*2) + 1] = 7;//7 + (XorShift32(threadID+1) % 15);
    }
    
    __syncthreads();

    GlobalData.NumbersToBeCalled[threadID] =
        1 + (SliceData[SliceIndex * 2] + ((numberIndex+1) * SliceData[(SliceIndex*2) + 1])) % GlobalData.MaxNumbers;
//    printf("ThreadID : %d, No : %d\n", threadIdx.x, GlobalData.NumbersToBeCalled[threadID]);
}

__global__ void
LoadCardDataKernel(card_load_memory_block GlobalData)
{
    __shared__ u8 Incrementer;
    extern __shared__ u8 ColumnSliceData[];

    u32 CellIndex = threadIdx.x % GlobalData.CardStride;
    u32 SliceIndex = threadIdx.x / GlobalData.CardStride;
    u32 threadID = (blockIdx.x * blockDim.x) + threadIdx.x;

    if(threadIdx.x == 0)
    {
        Incrementer = (GlobalData.MaxNumbers == 75) ? 3 : 5;
    }
    
    if(CellIndex == 0)
    {
        for(u32 ColumnIndex = 0;
            ColumnIndex < GlobalData.Row;
            ColumnIndex++)
        {
            u32 InitNumber = 1 + ColumnIndex * GlobalData.MaxNumberPerColumn;
            //StartNumber for this column slice
            ColumnSliceData[(SliceIndex * 2 * GlobalData.Row) + (ColumnIndex * 2)] = InitNumber + (XorShift32(threadID+1+ColumnIndex) % GlobalData.MaxNumberPerColumn);
            //IncrementNumber for this column slice
            ColumnSliceData[(SliceIndex * 2 * GlobalData.Row) + (ColumnIndex * 2) + 1] = InitNumber;
        }
    }
    
    __syncthreads();

    u32 ColumnIndex = CellIndex / GlobalData.Row;
    u32 numberIndex = CellIndex % GlobalData.Row;
    
    GlobalData.Cards[threadID] =
        ColumnSliceData[(SliceIndex * 2 * GlobalData.Row) + (ColumnIndex * 2) + 1] +
        (ColumnSliceData[(SliceIndex * 2 * GlobalData.Row) + (ColumnIndex * 2)] +
                     ((numberIndex+1) * Incrementer)) % GlobalData.MaxNumberPerColumn;
}

__global__ void
CardDaubKernel(memory_block GlobalData)
{
    //TODO(gerald): make sure the stride is aligned nicely
    __shared__ u32 CardStride;
    __shared__ u32 BlockStride;
    __shared__ u8 NumbersToBeCalled[MAX_NUMBER_CALL];//MaxNumbersToBeCalled

    //TODO(gerald): make sure the cards are aligned in a way there are no memory-bank conflicts
    extern __shared__ u32 CardInfos[];//count = sizeof(MaxCardsPerRoom * CardStride * sizeof(u32))
    
    //fill shared block info based on block idx
    if(threadIdx.x == 0)
    {
        CardStride = GlobalData.Row * GlobalData.Column;
        BlockStride = blockIdx.x * blockDim.x;
//        printf("BlockIdx : %d, Stride : %d\n", blockIdx.x, BlockStride);
    }

    __syncthreads();

    //load numbers to be called into shared memory
    if(threadIdx.x < 32)
    {
        NumbersToBeCalled[threadIdx.x] =
            GlobalData.NumbersToBeCalled[(blockIdx.x * MAX_NUMBER_CALL) + threadIdx.x];
    }
    

    __syncthreads();

    //load each card data
    for(u32 CellIndex = 0;
        CellIndex < CardStride;
        CellIndex++)
    {
        CardInfos[(threadIdx.x * CardStride) + CellIndex] =
            GlobalData.Cards[(BlockStride *  CardStride) + (threadIdx.x * CardStride) + CellIndex];
    }

    //daub numbers
    for(u32 DaubIndex = 0;
        DaubIndex < MAX_NUMBER_CALL;
        DaubIndex++)
    {
        for(u32 CellIndex = 0;
            CellIndex < CardStride;
            CellIndex++)
        {

            if((CardInfos[(threadIdx.x * CardStride) + CellIndex] & 0XFF) ==
               NumbersToBeCalled[DaubIndex])
            {
                CardInfos[(threadIdx.x * CardStride) + CellIndex] |= ((DaubIndex+1) << 8); 
                break;
            }
        }
    }

    //write back the results to the global memory
    for(u32 CellIndex = 0;
        CellIndex < CardStride;
        CellIndex++)
    {
        GlobalData.Cards[(BlockStride *  CardStride) + (threadIdx.x * CardStride) + CellIndex] =
            CardInfos[(threadIdx.x * CardStride) + CellIndex];
    }
}

int
main(void)
{
    u32 MaxRow = 5;
    u32 MaxColumn = 5;
    u32 MaxRooms = 1000;
    u32 MaxCardsPerRoom = 256;
    u32 MaxNumbers = 75;//60;

    u32 MaxBlocks = MaxRooms;
    u32 MaxThreadsPerBlock = MaxCardsPerRoom;
    u32 TotalCards = MaxRooms * MaxCardsPerRoom;

    //TODO(gerald):GetDevice list and get the max core based on the devices
    u32 DeviceMaxThreadPerBlock = 1024;
    
    memory_block HostData;
    HostData.Row = MaxRow;
    HostData.Column = MaxColumn;
    HostData.MaxCardCount = MaxThreadsPerBlock;
    HostData.MaxNumbersToBeCalled = MAX_NUMBER_CALL;

    u32 CardStride = HostData.Row * HostData.Column;
    memory_index NumbersCalledSizeInBytes = MaxBlocks * HostData.MaxNumbersToBeCalled * sizeof(u8);
    memory_index CardDataSizeInBytes = MaxBlocks * MaxThreadsPerBlock * CardStride * sizeof(u32);

    memory_index TotalSizeInBytes = NumbersCalledSizeInBytes + CardDataSizeInBytes;
    AlignByteSizeBy(TotalSizeInBytes, 8);

    //allocate & fill host data
    u8* HostMemoryPtr = (u8*)malloc(TotalSizeInBytes);
    HostData.NumbersToBeCalled = (u8*)HostMemoryPtr;
    HostData.Cards = (u32*)(HostMemoryPtr + NumbersCalledSizeInBytes);

//    u8 ColumnMaxNumbers[5] = {6, 6, 6, 7, 7};
    u8 MaxNumberPerColumn = MaxNumbers/HostData.Row;

#if 0    
    //host load numbers to be called
    for(u32 Index = 0;
        Index < HostData.MaxNumbersToBeCalled;
        Index++)
    {
        HostData.NumbersToBeCalled[Index] = 0xFF;
    }

    //host load card data
    for(u32 CellIndex = 0;
        CellIndex < CardStride;
        CellIndex++)
    {
        HostData.Cards[CellIndex] = 0xFF;
    }
#endif
    
    u8* DeviceMemoryPtr = 0;
    cudaMalloc(&DeviceMemoryPtr, TotalSizeInBytes);
//    cudaMemcpy(DeviceMemoryPtr, HostMemoryPtr, TotalSizeInBytes, cudaMemcpyHostToDevice);

    //gpu memory allocations
    memory_block DeviceData;
    DeviceData.Row = HostData.Row;
    DeviceData.Column = HostData.Column;
    DeviceData.MaxCardCount = HostData.MaxCardCount;
    DeviceData.MaxNumbersToBeCalled = MAX_NUMBER_CALL;
    DeviceData.NumbersToBeCalled = (u8*)DeviceMemoryPtr;
    DeviceData.Cards = (u32*)(DeviceMemoryPtr + NumbersCalledSizeInBytes);

    kernel_config NumbersLoadKernel;
    //NOTE(gerald): 256*125 = 32,000threads i.e 32 Numbers load for 1000 rooms
    NumbersLoadKernel.MaxBlocks = 125;
    NumbersLoadKernel.MaxThreadsPerBlock = 256;
    NumbersLoadKernel.DynamicSharedMemorySizeInBytes = 2 * sizeof(u8) * (NumbersLoadKernel.MaxThreadsPerBlock/MAX_NUMBER_CALL);
    AlignByteSizeBy(NumbersLoadKernel.DynamicSharedMemorySizeInBytes, 8);
    
    numbers_load_memory_block NumbersLoadData;
    NumbersLoadData.MaxNumbers = MaxNumbers;
    NumbersLoadData.NumbersToBeCalled = DeviceData.NumbersToBeCalled;
    //gpu load numbers to be called
    LoadNumbersToBeCalled<<<
            NumbersLoadKernel.MaxBlocks,
            NumbersLoadKernel.MaxThreadsPerBlock,
            NumbersLoadKernel.DynamicSharedMemorySizeInBytes
            >>>(NumbersLoadData);

    u32 CardCountPerBlock = DeviceMaxThreadPerBlock/CardStride;
    kernel_config CardLoadKernel;
    CardLoadKernel.MaxThreadsPerBlock = CardCountPerBlock * CardStride;
    CardLoadKernel.MaxBlocks = TotalCards/CardCountPerBlock;
    CardLoadKernel.DynamicSharedMemorySizeInBytes = 2 * sizeof(u8) * DeviceData.Row * CardCountPerBlock;
    AlignByteSizeBy(CardLoadKernel.DynamicSharedMemorySizeInBytes, 8);
    
    card_load_memory_block CardLoadData;
    CardLoadData.Row = DeviceData.Row;
    CardLoadData.Column = DeviceData.Column;
    CardLoadData.CardStride = CardStride;
    CardLoadData.MaxNumbers = MaxNumbers;
    CardLoadData.MaxNumberPerColumn = MaxNumbers/DeviceData.Column;
    CardLoadData.Cards = DeviceData.Cards;

    //gpu load card data
    LoadCardDataKernel<<<
            CardLoadKernel.MaxBlocks,
            CardLoadKernel.MaxThreadsPerBlock,
            CardLoadKernel.DynamicSharedMemorySizeInBytes
            >>>(CardLoadData);

    kernel_config DaubKernel;
    DaubKernel.MaxBlocks = MaxBlocks;
    DaubKernel.MaxThreadsPerBlock = MaxThreadsPerBlock;
    DaubKernel.DynamicSharedMemorySizeInBytes = DeviceData.MaxCardCount * CardStride * sizeof(u32);
    AlignByteSizeBy(DaubKernel.DynamicSharedMemorySizeInBytes, 8);
    //gpu card daub
    CardDaubKernel<<<
        DaubKernel.MaxBlocks,
        DaubKernel.MaxThreadsPerBlock,
        DaubKernel.DynamicSharedMemorySizeInBytes
            >>>(DeviceData);

#if 1    
    cudaDeviceSynchronize();
    cudaError_t ErrorCode = cudaPeekAtLastError();//cudaGetLastError();
    const char* ErrorText = cudaGetErrorString(ErrorCode);
    printf("%s\n\n", ErrorText);
#endif
    
    //copy device data back to host data
    cudaMemcpy(HostMemoryPtr, DeviceMemoryPtr, TotalSizeInBytes, cudaMemcpyDeviceToHost);

#if 1
    srand(time(0));
    u32 RoomIndex = rand() % MaxRooms;
    u32 CardIndex = rand() % CardCountPerBlock;
    printf("RoomConfig:\n");
    printf("\tTotalRooms : %d\n", MaxRooms);
    printf("\tCardsPerRoom : %d\n", MaxCardsPerRoom);
    printf("\tMaxNumbers : %d\n", MaxNumbers);
    printf("\n");
    
    printf("RoomIndex : %d\n", RoomIndex);
    printf("%d Nos called in the room :\n", MAX_NUMBER_CALL);
    //print called nos
    for(u32 NumberIndex = 0;
        NumberIndex < MAX_NUMBER_CALL;
        NumberIndex++)
    {
        u32 Index = (RoomIndex * MAX_NUMBER_CALL) + NumberIndex; 
        printf("%d, ", HostData.NumbersToBeCalled[Index]);
    }
    printf("\n\n");

    printf("CardIndex : %d\n", CardIndex);
    printf("CardData : No(DaubedIdx)\n");
    //print card data
    for(u32 ColumnIndex = 0;
        ColumnIndex < MaxColumn;
        ColumnIndex++)

    {
        for(u32 RowIndex = 0;
            RowIndex < MaxRow;
            RowIndex++)
        {
            u32 CellIndex = (RowIndex * MaxColumn) + ColumnIndex;
            u32 Index = (RoomIndex * MaxThreadsPerBlock * CardStride) + (CardIndex * CardStride) + CellIndex;
            u32 CardNo = HostData.Cards[Index] & 0xFF;;
            u32 DaubIndex = (HostData.Cards[Index] >> 8) & 0xFF;
            printf("%2d(%2d)  ", CardNo, DaubIndex);
        }
        printf("\n");
    }
#endif    

    cudaFree(DeviceMemoryPtr);
    free(HostMemoryPtr);
    return(0);
}
