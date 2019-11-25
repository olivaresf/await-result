# await-result
A simple function that transforms an asynchronous, completion-based, Result function into a synchronous, throwing function.

# The Problem
The following is a real-life example of one way to implement a CKShare:
1. You must first find if your share zone exists.
2. If your request succeeds (1a) and the zone exists (1b), you should see if you can discover the share participants.
3. If your request succeeds (2a) and the participants exist (2b), you should attempt to save the share.

As you can see, there are plenty of failure points:
1a. request may fail or time out
1b. the zone may not exist
2a. request may fail or time out
2b. the user may not exist
3. request may fail or time out

Since all three steps are asynchronous operations, you'd usually see something like the following snippet. Note that finding the failure points in the following piece of code is difficult.
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

The main issue is obvious: the code is not readable. Debugging is difficult, especially since we will not be printing, but handling errors in some way. This will add to code complexity and the method can easily become cumbersome.

Failure points are found in:

1a. request may fail or time out (line 65, indentation level 3)

1b. the zone may not exist (line 30, indentation level 4)

2a. request may fail or time out (line 60, indentation level 5)

2b. the user may not exist (line 42, indentation level 6)

3. request may fail or time out (line 55, indentation level 7)


Errors interfere with the reading flow, they get increasingly difficult to find as we go deeper into async hell, and errors in the first steps appear closer to the bottom, which is unintuitive.

# Proposed Solution
Use a simple function that transforms an asynchronous, completion-based, Result function into a synchronous throwing function.

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
    catch let error as AwaitError { 
        print("Operation timed out")
    }
    catch {
        print("Unknown error occurred")
    }
}
```

Failure points are found in:

1a. request may fail or time out (line 121, indentation level 2)

1b. the zone may not exist (line 96, indentation level 3)

2a. request may fail or time out (line 124, indentation level 2)

2b. the user may not exist (line 107, indentation level 3)

3. request may fail or time out (line 127, indentation level 2)


- Errors do not interfere with the reading flow. The happy path is immediately visible and easy to follow.
- Errors do not get increasingly difficult to find. Errors coming form async functions are after the happy path and errors coming from business logic are inside the happy path flow. 
- Errors in the first steps appear closer to the top, which is unintuitive.

# How to use it.

Take the first zone function in our example above. It has a function signature like so:

```func zoneExists(zoneName: String, completion: @escaping ((Result<ZoneState, ZoneExistsError>) -> Void)) {```

If we want to use `await-result` the function to be transformed _must_:
1. use Result as the only parameter in its completion block
2. be asynchronous.

Iff both of those are true, we can use `await` like so:

```
let zoneState = try await(asyncExecutionBlock: { asyncExecutionCompletedBlock in
    zoneExists(zoneName: aName) { zoneExistsResult in
        asyncExecutionCompletedBlock(zoneExistsResult)
    }
})
```

`await` will receive a block where the asynchronous code happens (asyncExecutionBlock). In the example above, asyncExecutionBlock is where we do our network call to see if the zone exists.

Once asyncExecutionBlock finishes, it, in turn, must call a completion block (asyncExecutionCompletedBlock) and hand over its Result.

The implementation's pseudo-code for `await` looks something like this:

```
func await(execution: @escaping (ExecutionCompletedBlock) -> Void)...

typealias ExecutionCompletedBlock = @escaping (Result<T, U>) -> Void
```

(Sidenote: Unfortunately, Swift's typealias does not currently support generics. I've only added it for clarity)

Now that `await` has its asyncExecutionBlock, it will:

1. Set up a semaphore that will block the thread `await` is being called on.

2. Execute asyncExecutionBlock

3. Tell the semaphore to wait and block the thread.

4. Once asyncExecutionBlock sends its Result by calling asyncExecutionCompletedBlock, it will decompose the Result into either success or failure and save whichever is unpacked.

5. Once it has the unpacked result, it unblocks the thread.

6. Then it checks if there was an error. If there was, throw.

7. If no errors were present, it returns the success value.


In the case of our example, the function `zoneExists` returns a result of type `Result<ZoneState, ZoneExistsError>`. Using type inference, `await` will `throw ZoneExistsError` if step 6 fails and it will return a `ZoneState` object if step 7 succeeds. 

Now that we know all this, we can simplify the code.

```
0. Original code.
let zoneState = try await(asyncExecutionBlock: { asyncExecutionCompletedBlock in
    zoneExists(zoneName: aName) { zoneExistsResult in
        asyncExecutionCompletedBlock(zoneExistsResult)
    }
})
```

Remove the label for `asyncExecutionBlock`.
```
let zoneState = try await { asyncExecutionCompletedBlock in
    zoneExists(zoneName: aName) { zoneExistsResult in
        asyncExecutionCompletedBlock(zoneExistsResult)
    }
}
```

2. Since we're only passing along our result, zoneExistsResult's label is unnecessary.
```
let zoneState = try await { asyncExecutionCompletedBlock in
    zoneExists(zoneName: aName) {
        asyncExecutionCompletedBlock($0)
    }
}
```

3. Compress spacing to increase readability
```
let zoneState = try await { finished in
    zoneExists(zoneName: aName) { finished($0) }
}
```
