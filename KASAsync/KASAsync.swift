import Foundation


prefix operator <~ {}
prefix operator <!= {}
prefix operator <= {}

prefix func <~ <T : Awaitable> (awaitable: T) -> T.ReturnType {
    return awaitable.await()
}

prefix func <!= <T> (task: Void -> T) -> T {
    return Task.runInMainQueue(task).await()
}

prefix func <= <T> (task: Void -> T) -> T {
    return Task.run(task).await()
}



public class Barrier {
    private var semaphore: dispatch_semaphore_t? = dispatch_semaphore_create(0)
    
    public func waitForUnlock() {
        if let semaphore = semaphore {
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
            self.semaphore = nil
        }
    }
    
    public func unlock() {
        precondition(semaphore != nil, "Barrier has been already unlocked")
        dispatch_semaphore_signal(semaphore)
    }
}


protocol Awaitable {
    typealias ReturnType
    
    func await() -> ReturnType
}



public class Promise<T> : Awaitable {
    typealias ReturnType = T

    public var result: ReturnType? {
        didSet {
            barrier.unlock()
        }
    }
    private let barrier = Barrier()

    public init() {
    }

    public func await() -> ReturnType {
        barrier.waitForUnlock()
        return result!
    }
}


public class AwaitableTask<T> : Awaitable {
    typealias ReturnType = T

    private let taskWithResult: Void->ReturnType
    
    private init(taskWithResult: Void->ReturnType) {
        self.taskWithResult = taskWithResult
    }
    
    public func await() -> ReturnType {
        return taskWithResult();
    }
}


public class Task<ReturnType> {
    public class func run(task: Void->ReturnType) -> AwaitableTask<ReturnType> {
        return self.runInQueue(QueueRetriever.defaultQueue, task: task)
    }
    
    public class func runInBackground(task: Void->ReturnType) -> AwaitableTask<ReturnType> {
        return self.runInQueue(QueueRetriever.backgroundQueue, task: task)
    }

    public class func runInMainQueue(task: Void->ReturnType) -> AwaitableTask<ReturnType> {
        return self.runInQueue(QueueRetriever.mainQueue, task: task)
    }

    public class func runInQueue(queue: dispatch_queue_t, task: Void->ReturnType) -> AwaitableTask<ReturnType> {
        let group = dispatch_group_create()
        var result: ReturnType!
        dispatch_group_async(group, queue) {
            result = task()
        }
        return AwaitableTask() {
            dispatch_group_wait(group, DISPATCH_TIME_FOREVER)
            return result
        }
    }
}

// MARK: Private components

private class QueueRetriever {
    class var defaultQueue: dispatch_queue_t {
        return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
    }
    
    class var backgroundQueue : dispatch_queue_t {
        return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)
    }
    
    class var mainQueue : dispatch_queue_t {
        return dispatch_get_main_queue()
    }
}
