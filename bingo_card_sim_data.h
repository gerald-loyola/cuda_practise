#if !defined(BINGO_CARD_SIM_DATA_H)

#define BINGO_CARD_SIM_DATA_H

#include "type.h"

typedef struct
{
    u32 MaxBlocks;
    u32 MaxThreadsPerBlock;
    memory_index DynamicSharedMemorySizeInBytes;
}kernel_config;

typedef struct
{
    u32 Row;
    u32 Column;
    u32 MaxCardCount;
    u32 MaxNumbersToBeCalled;

    u8* NumbersToBeCalled;
    u32* Cards;
}memory_block;


typedef struct
{
    u32 MaxNumbers;
    u32 MaxRoomCount;
    u8* NumbersToBeCalled;
}numbers_load_memory_block;

typedef struct
{
    u8 Row;
    u8 Column;
    u8 CardStride;
    u8 MaxNumbers;
    u8 MaxNumberPerColumn;
    u32* Cards;
}card_load_memory_block;

#endif
