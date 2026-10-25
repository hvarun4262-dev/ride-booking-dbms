import asyncio
import httpx

async def attempt_accept(client, driver_id, ride_id):
    # Uses the shared client to prevent TCP handshake delays
    response = await client.post(
        f"http://127.0.0.1:8000/rides/{ride_id}/accept", 
        json={"driver_id": driver_id}
    )
    return response

async def test_driver_double_booking_lock():
    driver_id = 1
    # NOTE: Ensure rides 101 and 102 actually exist in your DB and are in 'requested' status
    ride_id_1 = 101 
    ride_id_2 = 102 
    
    # Open a single client session for true concurrent firing
    async with httpx.AsyncClient() as client:
        # asyncio.gather fires both requests at the exact same millisecond
        results = await asyncio.gather(
            attempt_accept(client, driver_id, ride_id_1),
            attempt_accept(client, driver_id, ride_id_2)
        )
    
    status_codes = [res.status_code for res in results]
    print(f"Server returned status codes: {status_codes}")
    
    # Assertions with helpful error messages
    assert 200 in status_codes, "Neither request succeeded. Did you seed rides 101 and 102 as 'requested'?"
    assert status_codes.count(200) == 1, "Race condition failed! The lock allowed the driver to accept both."
    
    print("✅ Concurrency test passed! Lock successfully prevented the driver from double-booking.")

if __name__ == "__main__":
    asyncio.run(test_driver_double_booking_lock())