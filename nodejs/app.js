const express = require('express')
const app = express()

var basicAuth = require('basic-auth');

var auth = function (req, res, next) {
  function unauthorized(res) {
    res.set('WWW-Authenticate', 'Basic realm=Authorization Required');
    return res.sendStatus(401);
  };

  var user = basicAuth(req);

  if (!user || !user.name || !user.pass) {
    console.log(req.url + " access denied. missing authentication header");
    return unauthorized(res);
  };

  if (user.name === 'fulano' && user.pass === 'silva') {
    console.log(req.url + " access granted for user " + user.name);
    return next();
  } else {
    console.log(req.url + " access denied. invalid user credentials user " + user.name);
    return unauthorized(res);
  };
};

var bodyParser = require("body-parser");
app.use(bodyParser.urlencoded({extended:false}));
app.use(bodyParser.json());

const port = 51398

app.get('/test', auth, (req, res) => {
  console.log('Test authenticated!');
  res.end('Welcome test');
})

app.post('/public', (req, res) => {
  console.log('Received a public event ' + req.url)
  console.log(req.body);
  res.end('')
})

app.post('/', auth, (req, res) => {
  console.log('Received a private event ' + req.url)
  console.log(req.body);
  res.end('')
})

app.listen(port, () => console.log('Example app listening on port '+port))
