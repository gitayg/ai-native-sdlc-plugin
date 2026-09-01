// The other direction of the survey: a tree that does state its behaviour to a
// machine. Routes, exported symbols, config key names and thrown errors are all
// here, so the strong tier clears its floor and the survey draws a draft tier.
// A surveyor that always refuses would be as useless as one that never does.
const router = createRouter();

router.get('/widgets', (req, res) => res.json(listWidgets()));
router.post('/widgets', (req, res) => res.json(createWidget(req.body)));
router.get('/widgets/:id', (req, res) => res.json(getWidget(req.params.id)));
router.delete('/widgets/:id', (req, res) => res.json(removeWidget(req.params.id)));

const PORT = process.env.WIDGET_PORT || 8080;
const RETRIES = process.env.WIDGET_RETRIES || 3;
const MODE = process.env.WIDGET_MODE || 'batch';

function createRouter() {
  return { get() {}, post() {}, delete() {} };
}

function listWidgets() {
  return [];
}

function createWidget(body) {
  if (!body) throw new Error('a widget needs a body');
  return body;
}

function getWidget(id) {
  if (!id) throw new Error('a widget needs an id');
  return { id };
}

function removeWidget(id) {
  if (!id) throw new Error('a widget needs an id to remove');
  return { id, removed: true };
}

module.exports = { router, PORT, RETRIES, MODE, listWidgets, createWidget, getWidget, removeWidget };
