const express = require('express')
const app = express()
var bodyParser = require("body-parser");
app.use(bodyParser.urlencoded({extended:false}));
app.use(bodyParser.json());

const port = 51398

app.post('/', (req, res) => {  
  console.log('Received')
  console.log(req.body);
  res.end('')
}, (err) => console.log('Some error occured:' + err))

app.listen(port, () => console.log('Example app listening on port '+port))
