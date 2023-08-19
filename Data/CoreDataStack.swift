//
//  CoreDataStack.swift
//  ChartInsight
//
//  Created by Eric Kennedy on 8/19/23.
//  Copyright © 2023 Chart Insight LLC. All rights reserved.
//

import CoreData
import Foundation

public final class CoreDataStack {
    static let shared = CoreDataStack(modelName: "CoreDataModel")

    private let modelName: String

    public init(modelName: String) {
        self.modelName = modelName
    }

    public lazy var container: NSPersistentContainer = {
        let container = NSPersistentContainer(name: self.modelName)
        container.loadPersistentStores { _, error in
            container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            if let error {
                print("Unresolved error \(error)")
            }
        }
        return container
    }()

    public lazy var viewContext: NSManagedObjectContext = {
        let context = container.viewContext
        context.automaticallyMergesChangesFromParent = true
        return context
    }()

    public func save() {
        do {
            try container.viewContext.save()
        } catch {
            print("Error occured while saving \(error)")
        }
    }

}
