const fs = require("fs");
const path = require("path");
import { AbiCoder } from "@ethersproject/abi";
import { task } from "hardhat/config";

const basePath = "contracts/facets/";
const libraryBasePath = "contracts/libraries/";
//const sharedLibraryBasePath = "/contracts/shared/libraries/";

function recFindByExt(base, ext, files, result) {
  files = files || fs.readdirSync(base);
  result = result || [];

  files.forEach(function (file) {
    var newbase = path.join(base, file);
    if (fs.statSync(newbase).isDirectory()) {
      result = recFindByExt(newbase, ext, fs.readdirSync(newbase), result);
    } else {
      if (file.substr(-1 * (ext.length + 1)) == "." + ext) {
        if (file.toUpperCase().endsWith("FACET.SOL")) result.push(newbase);
      }
    }
  });
  return result;
}

task(
  "diamondABI",
  "Generates ABI file for diamond, includes all ABIs of facets"
).setAction(async () => {
  let files = recFindByExt("./" + basePath, "sol", null, null);
  console.log(files);
  let abi: AbiCoder[] = [];
  for (const file of files) {
    const jsonFile = file.replace(/^.*[\\\/]/, '').replace("sol", "json");
    let fileAddress = `./artifacts/${file}/${jsonFile}`;
    let json = fs.readFileSync(fileAddress);
    json = JSON.parse(json);
    abi.push(...json.abi);
  
  }
  files = recFindByExt("./" + libraryBasePath, "sol", null, null);
  for (const file of files) {
    const jsonFile = file.replace("sol", "json");
    let json = fs.readFileSync(
      `./artifacts/${libraryBasePath}${file}/${jsonFile}`
    );
    json = JSON.parse(json);
    abi.push(...json.abi);
  }
  //   files = fs.readdirSync("." + sharedLibraryBasePath);
  //   for (const file of files) {
  //     const jsonFile = file.replace("sol", "json");
  //     let json = fs.readFileSync(
  //       `./artifacts/${sharedLibraryBasePath}${file}/${jsonFile}`
  //     );
  //     json = JSON.parse(json);
  //     abi.push(...json.abi);
  //   }
  let finalAbi = JSON.stringify(abi);
  fs.writeFileSync("./diamondABI/diamond.json", finalAbi);
  console.log("ABI written to diamondABI/diamond.json");
});
