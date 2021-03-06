// Copyright 2014-2015 Ben Hale. All Rights Reserved

import CloudKit
import Foundation


final class DistilleryRepository {

    static let instance = DistilleryRepository()

    typealias Listener = [Distillery]? -> Void

    private let cacheURL = URLForCached("Distilleries")

    private let database = CKContainer.defaultContainer().publicCloudDatabase

    private var distilleries: [Distillery]? {
        didSet {
            synchronized(self.monitor) {
                for listener in self.listeners.values {
                    listener(self.distilleries)
                }
            }
        }
    }

    private var listeners: [Memento : Listener] = [:]

    private let logger = Logger(name: "DistilleryRepository")

    private let monitor = Monitor()

    private let predicate = NSPredicate(format: "TRUEPREDICATE")

    private let recordType = "Distillery"

    private init() {
        self.distilleries = fetchFromCache()
        Subscription(recordType: recordType, database: self.database, predicate: self.predicate, notificationHandler: fetchFromCloudKit)
    }

    func delete(distillery: Distillery?) {
        if let distillery = distillery {
            self.logger.debug { "Deleting distillery \(distillery)" }

            self.database.deleteRecordWithID(distillery.toRecord().recordID) { recordId, error in
                if error != nil {
                    //TODO: Handle error deleting record
                    self.logger.error { "Error deleting distillery: \(error)" }
                    return
                }

                self.distilleries = self.distilleries?.filter { $0.toRecord().recordID != recordId }
                self.saveToCache(self.distilleries)
                self.logger.info { "Deleted distillery: \(distillery)" }
            }
        }
    }

    func save(distillery: Distillery?) {
        if let distillery = distillery {
            self.logger.debug { "Saving distillery \(distillery)" }

            self.database.saveRecord(distillery.toRecord()) { record, error in
                if error != nil {
                    // TODO: Handle error saving record
                    self.logger.error { "Error saving distillery: \(error)"}
                    return
                }

                let distillery = Distillery(record: record)
                if var distilleries = self.distilleries {
                    distilleries.append(distillery)
                    self.distilleries = distilleries.sorted { $0 < $1 }
                } else {
                    self.distilleries = [distillery]
                }

                self.saveToCache(self.distilleries)
                self.logger.info { "Saved distillery: \(distillery)" }
            }
        }
    }

    func subscribe(listener: Listener) -> Memento {
        return synchronized(self.monitor) {
            let memento = Memento()
            self.listeners[memento] = listener
            listener(self.distilleries)
            return memento
        }
    }

    func unsubscribe(memento: Memento?) {
        if let memento = memento {
            synchronized(self.monitor) {
                self.listeners[memento] = nil
            }
        }
    }

    private func fetchFromCache() -> [Distillery]? {
        if let cacheURL = self.cacheURL {
            self.logger.debug { "Fetching cached distilleries" }

            if let data = NSData(contentsOfURL: cacheURL) {
                let distilleries = NSKeyedUnarchiver.unarchiveObjectWithData(data) as? [Distillery]
                self.logger.debug { "Fetched cached distilleries: \(distilleries)" }
                return distilleries
            } else {
                self.logger.debug { "No cached distilleries to fetch" }
                return nil
            }
        } else {
            self.logger.warn { "Unable to fetch cached distilleries" }
            return nil
        }
    }

    private func fetchFromCloudKit() {
        self.logger.debug { "Fetching distilleries" }

        var distilleries: [Distillery] = []
        fetchFromCloudKit(&distilleries, query: CKQuery(recordType: self.recordType, predicate: self.predicate))
    }

    private func fetchFromCloudKit(inout distilleries: [Distillery], cursor: CKQueryCursor? = nil, query: CKQuery? = nil) {
        let operation: CKQueryOperation

        if let cursor = cursor {
            operation = CKQueryOperation(cursor: cursor)
        } else if let query = query {
            operation = CKQueryOperation(query: query)
        } else {
            self.logger.warn { "Unable to fetch from CloudKit without a cursor or query" }
            return
        }

        operation.recordFetchedBlock = { distilleries.append(Distillery(record: $0)) }
        operation.queryCompletionBlock = { cursor, error in
            if error != nil {
                // TODO: Handle error performing query
                self.logger.error { "Error fetching distilleries: \(error)" }
                return
            }

            if cursor != nil {
                self.logger.debug { "Fetching more distilleries" }
                self.fetchFromCloudKit(&distilleries, cursor: cursor)
                return
            }

            distilleries.sort { $0 < $1 }
            self.saveToCache(distilleries)

            self.logger.info { "Fetched distilleries: \(distilleries)" }
            self.distilleries = distilleries
        }

        self.database.addOperation(operation)
    }

    private func saveToCache(distilleries: [Distillery]?) {
        switch (distilleries, self.cacheURL) {
        case (.Some(let distilleries), .Some(let cacheURL)):
            NSKeyedArchiver.archivedDataWithRootObject(distilleries).writeToURL(cacheURL, atomically: true)
            self.logger.debug { "Saved cached distilleries: \(distilleries)" }
        case (.None, .Some(let cacheURL)):
            NSFileManager.defaultManager().removeItemAtURL(cacheURL, error: nil)
            self.logger.debug { "Removed cached distilleries"}
        default:
            self.logger.warn { "Unable to save cached distilleries" }
        }
    }

}
