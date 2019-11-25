//
//  Await-Result.swift
//  Amazing Humans
//
//  Created by Fernando Olivares on 11/24/19.
//  Copyright © 2019 Fernando Olivares. All rights reserved.

import Foundation

enum AwaitError : Error {
	case timeOut
}

func await<T, U>(timeout: DispatchTime? = nil, execution: @escaping (@escaping (Result<T, U>) -> Void) -> Void) throws -> T {
	
	let semaphore = DispatchSemaphore(value: 0)
	var possibleSuccess: T? = nil
	var possibleError: U? = nil
	
	execution { result in
		switch result {
		case .success(let success): possibleSuccess = success
		case .failure(let error): possibleError = error
		}
		semaphore.signal()
	}
	
	let _ = semaphore.wait(timeout: timeout ?? .now() + 10)
	guard possibleError == nil else {
		throw possibleError!
	}
	
	guard let success = possibleSuccess else {
		throw AwaitError.timeOut
	}
	
	return success
}
