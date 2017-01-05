#include "hash.hlsli"
#include "loadConstantsGPU.h"

RWBuffer<float> output : register(u0);
ByteAddressBuffer sourceData : register(t0);

cbuffer CB0 : register(b0)
{
	LoadConstants loadConstants;
};

#define THREAD_GROUP_SIZE 256

groupshared float dummyLDS[THREAD_GROUP_SIZE];

[numthreads(THREAD_GROUP_SIZE, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID, uint gix : SV_GroupIndex)
{
	float4 value = 0.0;
	
#if defined(LOAD_INVARIANT)
    // All threads load from same address. Index is wave invariant.
	uint htid = 0;
#elif defined(LOAD_LINEAR)
	// Linearly increasing starting address to allow memory coalescing
	uint htid = gix;
#elif defined(LOAD_RANDOM)
    // Randomize start address offset (0-15) to prevent memory coalescing
	uint htid = hash1(gix) & 0xf;
#endif

	for (int i = 0; i < 256; ++i)
	{
		uint elemIdx = (htid + i) & loadConstants.elementsMask;
#if LOAD_WIDTH == 1
		value += sourceData.Load(elemIdx * 4).xxxx;
#elif LOAD_WIDTH == 2
		value += sourceData.Load2(elemIdx * 8).xyxy;
#elif LOAD_WIDTH == 4
		value += sourceData.Load4(elemIdx * 16).xyzw;
#endif
	}

    // Linear write to LDS (no bank conflicts). Significantly faster than memory loads.
	dummyLDS[gix] = value.x + value.y + value.z + value.w;

	GroupMemoryBarrierWithGroupSync();

	// This branch is never taken, but the compiler doesn't know it
	// Optimizer would remove all the memory loads if the data wouldn't be potentially used
	[branch]
	if (loadConstants.writeIndex != 0xffffffff)
	{
        output[tid.x + tid.y] = dummyLDS[loadConstants.writeIndex];
    }
}