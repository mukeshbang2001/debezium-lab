// Create DB & Collection
db = db.getSiblingDB("shop");

//db.createCollection("customers");

// Insert sample customers
db.customers.insertMany([
  { _id: 1, name: "John", age: 30, city: "Bangalore" },
  { _id: 2, name: "Priya", age: 28, city: "Mumbai" }
]);

