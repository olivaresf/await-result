# await-result
A simple function that transforms an asynchronous, completion-based, Result function into a synchronous, throwing function.

This is function I built to reduce async hell in Swift.

The following is a real-life example of one way to implement a CKShare:
1. You must first find if your share zone exists.
2. If your request succeeds (1a) and the zone exists (1b), you should see if you can discover the share participants.
3. If your request succeeds (2a) and the participants exist (2b), you should attempt to save the share.

Since all three steps are asynchronous operations, you'd usually see something like this:
```
func attemptToShare(groupViewModel: GroupViewModel, from controller: UIViewController) {
		
    // 1a. Can we find an existing sharing zone?
    cloudKitCoordinator.zoneExists(zoneName: groupsZoneIdentifier) { zoneExistsResult in
        
        switch zoneExistsResult {
				
        case .success(let zoneExists):
        
            //1.a Did we find it?
            guard case .found(let zoneID) = zoneExists else { 
                print("Zone not found")
                return 
            }
				
            // 2a. Can we find the user they want to share it with?
            cloudKitCoordinator.discoverUserWithEmail { discoverUserResult in

                switch discoverUserResult {

                case .success(let possibleIdentity):
                    // 2.b  Did we find it?
                    guard let identity = possibleIdentity else { 
                        print("User not found")
                        return
                    }

                    // 3. We have a group, the participants, and the zone. Can we share?
                    let group = Group(name: groupViewModel.name)
                    self.cloudKitCoordinator.share(group: group, with: [identity], in: zone) { shareResult in

                        switch shareResult {
                        case .success(let record):
                            print("Shared!")

                        case .failure(let error):
                            print("Failed sharing record")
                        }
                    }

                case .failure(let error):
                    print("Failed discovering user")
                }
            }
				
        case .failure(let error):
            print("Failed finding zone")
        }
    }
}
```

to this:

```
func attemptToShare(groupViewModel: GroupViewModel, from controller: UIViewController) {
		
    do {
        // 1a. Can we find an existing sharing zone?
        let didFindZoneIDResult = try await { awaitCompletion in
            self.cloudKitCoordinator.zoneExists(zoneName: self.sharedGroupsZoneIdentifier) { awaitCompletion($0) }
        }
			
        // 1.b Did we find it?
        guard case .found(let foundZoneID) = didFindZoneIDResult else { 
            print("Zone not found")
            return 
        }
			
        // 2a. Can we find the user they want to share it with?
        let possibleUserIdentity = try await { awaitCompletion in
            self.cloudKitCoordinator.discoverUserWithEmail { awaitCompletion($0) }
        }
			
        // 2b. Did we find it?
        guard let userIdentity = possibleUserIdentity else {
            print("User not found")
            return
        }
			
        // 3. We have a group, the participants, and the zone. Can we share?
        let group = Group(name: groupViewModel.name)   
        let invites = try await { awaitCompletion in
            self.cloudKitCoordinator.share(group: group, with: [userIdentity], in: foundZoneID) { awaitCompletion($0) }
        }
            
        // We successfuly invited people.
        print("Shared!")
    }
    catch let error as CloudKitCoordinator.ZoneExistsError {
        print("Failed finding zone")
    }
    catch let error as CloudKitCoordinator.DiscoverUserError {
        print("Failed discovering user")
    }
    catch let error as CloudKitCoordinator.ShareError {
        print("Failed sharing record")
    }
    catch { 
        print("Unknown error occurred")
    }
}
```
