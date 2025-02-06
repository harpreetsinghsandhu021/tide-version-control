const fs = require('fs');
const zlib = require('zlib');

const filePath = process.argv[2]; 

if (!filePath) {
  console.error("Please provide the file path as an argument.");
  process.exit(1);
}

fs.readFile(filePath, (err, data) => {
  if (err) {
    console.error(`Error reading file: ${err}`);
    process.exit(1);
  }

  zlib.inflate(data, (err, result) => {
    if (err) {
      console.error(`Error inflating data: ${err}`);
      process.exit(1);
    }

    console.log(result.toString()); 
  });
});