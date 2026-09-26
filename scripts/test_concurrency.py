import requests
import concurrent.futures
import time

# Ensure your FastAPI server is running on port 8000 before executing this
BASE_URL = "http://127.0.0.1:8000/rides"
RIDE_ID = 4 # Make sure Ride 4 exists in your DB and has status = 'requested'

def driver_accepts_ride(driver_id):
    """Simulates a driver hitting the 'accept' API endpoint."""
    print(f"[Driver {driver_id}] Attempting to accept Ride {RIDE_ID}...")
    
    # We use PUT as defined in our FastAPI routes
    url = f"{BASE_URL}/{RIDE_ID}/accept"
    payload = {"driver_id": driver_id}
    
    # Record exactly when the request was sent
    start_time = time.time()
    response = requests.put(url, json=payload)
    end_time = time.time()
    
    elapsed = round((end_time - start_time) * 1000, 2)
    
    if response.status_code == 200:
        print(f"✅ [Driver {driver_id}] SUCCESS in {elapsed}ms! {response.json()}")
    else:
        print(f"❌ [Driver {driver_id}] FAILED in {elapsed}ms. Reason: {response.json()}")

def run_race_condition():
    print(f"--- STARTING CONCURRENCY TEST FOR RIDE {RIDE_ID} ---")
    
    # ThreadPoolExecutor fires both functions simultaneously
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        # Driver 10 and Driver 11 race to accept the ride
        executor.submit(driver_accepts_ride, 10)
        executor.submit(driver_accepts_ride, 11)
        
    print("--- TEST COMPLETE ---")

if __name__ == "__main__":
    # You will need to pip install requests if you haven't already:
    # pip install requests
    run_race_condition()