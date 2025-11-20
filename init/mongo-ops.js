db = db.getSiblingDB("shop");

// Insert new
db.customers.insertOne({ _id: 3, name: "Sanjay", age: 40, city: "Delhi" });

// Update
db.customers.updateOne({ _id: 1 }, { $set: { age: 31 } });

// Delete
db.customers.deleteOne({ _id: 2 });

// Insert multiple
db.customers.insertMany([
  { _id: 4, name: "Meera", age: 25, city: "Hyderabad" },
  { _id: 5, name: "Rishi", age: 27, city: "Chennai" }
]);

